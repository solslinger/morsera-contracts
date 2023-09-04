// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {GnosisSafe, Enum} from "safe-contracts/GnosisSafe.sol";
import {Guard} from "safe-contracts/base/GuardManager.sol";

import {IERC165} from "forge-std/interfaces/IERC165.sol";

import {OnlyDelegateCall} from "./OnlyDelegateCall.sol";
import {IDeadManSwitch} from "./interfaces/IDeadManSwitch.sol";
import {ISecondaryGuard} from "./interfaces/ISecondaryGuard.sol";

/// @title DeadManSwitch
/// @notice When added to a Gnosis Safe as a module and guard, allows arbitrary transactions to be executable after some amount of time.
contract DeadManSwitch is IDeadManSwitch {
    /// @inheritdoc IDeadManSwitch
    GnosisSafe public override immutable safe;
    /// @inheritdoc IDeadManSwitch
    uint256 public override lastInteractionTimestamp;
    /// @inheritdoc IDeadManSwitch
    uint256 public override scheduledTxCount;

    /// @inheritdoc IDeadManSwitch
    ISecondaryGuard public override secondaryGuard;

    /// @dev maps txHash to ScheduledTxInfo
    mapping(bytes32 => ScheduledTxInfo) private _scheduledTx;

    constructor(GnosisSafe _safe) {
        safe = _safe;
        lastInteractionTimestamp = block.timestamp;
    }

    /// @dev Allows only the safe to call a function
    modifier onlySafe() {
        if (msg.sender != address(safe)) {
            revert NotGnosisSafe();
        }
        _;
    }

    /// @inheritdoc IDeadManSwitch
    function setSecondaryGuard(ISecondaryGuard _secondaryGuard) external override onlySafe {
        secondaryGuard = _secondaryGuard;
        emit SecondaryGuardSet(address(_secondaryGuard));
    }

    /// @inheritdoc IDeadManSwitch
    function scheduleTx(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        TriggerType triggerType,
        uint240 triggerTime,
        bytes32 predecessor
    ) external override onlySafe returns (bytes32) {
        // if trigger type is timestamp, make sure it is in the future
        if (triggerType == TriggerType.Timestamp && block.timestamp >= triggerTime) {
            revert TriggerTimeTooEarly(triggerTime);
        }

        if (predecessor != 0 && _scheduledTx[predecessor].state != TxState.Pending) {
            revert PredecessorNotPending(predecessor, _scheduledTx[predecessor].state);
        }

        uint256 nonce = scheduledTxCount++;
        bytes32 txHash = calculateTxHash(to, value, data, operation, nonce);

        _scheduledTx[txHash] = ScheduledTxInfo({
            state: TxState.Pending,
            triggerType: triggerType,
            triggerTime: triggerTime,
            predecessor: predecessor
        });

        emit ScheduledTx(txHash, to, value, data, operation, nonce, triggerType, triggerTime, predecessor);

        return txHash;
    }

    /// @inheritdoc IDeadManSwitch
    function cancelTx(bytes32 txHash) external override onlySafe {
        ScheduledTxInfo storage info = _scheduledTx[txHash];

        if (info.state != TxState.Pending) {
            revert TxNotPending(txHash);
        }

        info.state = TxState.Cancelled;

        emit CancelledTx(txHash);
    }

    /// @inheritdoc IDeadManSwitch
    function executeTx(address to, uint256 value, bytes memory data, Enum.Operation operation, uint256 nonce)
        external
        override
    {
        bytes32 txHash = calculateTxHash(to, value, data, operation, nonce);

        ScheduledTxInfo storage infoPtr = _scheduledTx[txHash];
        ScheduledTxInfo memory info = infoPtr;

        if (info.state != TxState.Pending) {
            revert TxNotPending(txHash);
        }

        if (info.triggerType == TriggerType.Timestamp && block.timestamp < info.triggerTime) {
            revert TooEarlyToExecute(info.triggerTime);
        }
        if (
            info.triggerType == TriggerType.InteractionTimeout
                && block.timestamp < lastInteractionTimestamp + info.triggerTime
        ) {
            revert TooEarlyToExecute(lastInteractionTimestamp + info.triggerTime);
        }

        // if predecessor is nonzero, make sure it is executed (cancelled txs are NOT considered executed)
        if (info.predecessor != 0 && _scheduledTx[info.predecessor].state != TxState.Executed) {
            revert PredecessorNotExecuted(info.predecessor, _scheduledTx[info.predecessor].state);
        }

        infoPtr.state = TxState.Executed;

        bool success = safe.execTransactionFromModule(to, value, data, operation);

        if (!success) {
            revert TxFailed(txHash);
        }

        emit ExecutedTx(txHash);
    }

    /// @notice Guard function. Called by Safe before executing a transaction. 
    ///         Stores the block.timestamp and if there is a secondary guard, calls it
    function checkTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures,
        address msgSender
    ) external override onlySafe {
        // store current timestamp
        lastInteractionTimestamp = block.timestamp;

        // check the secondary guard if it is set
        if (address(secondaryGuard) != address(0)) {
            secondaryGuard.checkTransaction({
                safe: address(safe),
                to: to,
                value: value,
                data: data,
                operation: operation,
                safeTxGas: safeTxGas,
                baseGas: baseGas,
                gasPrice: gasPrice,
                gasToken: gasToken,
                refundReceiver: refundReceiver,
                signatures: signatures,
                msgSender: msgSender
            });
        }
    }

    /// @notice Guard function. Called by Safe after a tx is executed.
    ///         If there is a secondary guard, call it.
    /// @dev    Has `onlySafe` in case the secondary guard needs access control.
    function checkAfterExecution(bytes32 txHash, bool success) external override onlySafe {
        if (address(secondaryGuard) != address(0)) {
            secondaryGuard.checkAfterExecution(address(safe), txHash, success);
        }
    }

    /// @notice IERC165. Returns true for `Guard`, `IERC165`, and `IDeadManSwitch`
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(Guard).interfaceId // 0xe6d7a83a
            || interfaceId == type(IERC165).interfaceId // 0x01ffc9a7
            || interfaceId == type(IDeadManSwitch).interfaceId; // ???
    }

    /// @inheritdoc IDeadManSwitch
    function scheduledTx(bytes32 txHash) external view override returns (ScheduledTxInfo memory) {
        return _scheduledTx[txHash];
    }

    /// @inheritdoc IDeadManSwitch
    function calculateTxHash(address to, uint256 value, bytes memory data, Enum.Operation operation, uint256 nonce)
        public
        pure
        override
        returns (bytes32)
    {
        return keccak256(abi.encode(to, value, data, operation, nonce));
    }
}
