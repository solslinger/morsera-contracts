// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {Guard} from "safe-contracts/base/GuardManager.sol";
import {IERC165} from "forge-std/interfaces/IERC165.sol";
import {GnosisSafe, Enum} from "safe-contracts/GnosisSafe.sol";

import {ISecondaryGuard} from "./ISecondaryGuard.sol";

/// @title IDeadManSwitch
/// @notice Interface for the DeadManSwitch contract
interface IDeadManSwitch is Guard, IERC165 {
    /// @notice TriggerType indicates the type of trigger for a scheduled transaction
    ///         Timestamp: the transaction will be executed at a specific timestamp
    ///         InteractionTimeout: the transaction will be executed if there is no interaction with the safe for the specified timeout
    enum TriggerType {
        Timestamp,
        InteractionTimeout
    }

    /// @notice TxState indicates the state of a scheduled transaction
    ///         None: the transaction has not been scheduled
    ///         Pending: the transaction has been scheduled but not executed
    ///         Executed: the transaction has been executed
    ///         Cancelled: the transaction has been cancelled
    enum TxState {
        None,
        Pending,
        Executed,
        Cancelled
    }

    /// @notice ScheduledTxInfo contains information about a scheduled transaction
    /// @param  state state of the transaction
    /// @param  triggerType type of trigger for the transaction
    /// @param  triggerTime time value for the trigger
    /// @param  predecessor hash of the predecessor transaction
    ///                     (predecessor must be executed before this transaction can be executed)
    struct ScheduledTxInfo {
        TxState state;
        TriggerType triggerType;
        uint240 triggerTime;
        bytes32 predecessor;
    }

    /// @notice ScheduledTx is emitted when a transaction is scheduled
    /// @param  txHash hash of the transaction
    /// @param  to target address of the transaction
    /// @param  value value of the transaction
    /// @param  data data of the transaction
    /// @param  operation operation of the transaction (Call or DelegateCall)
    /// @param  nonce nonce of the transaction (separate from the safe nonce)
    /// @param  triggerType type of trigger for the transaction
    /// @param  triggerTime time value for the trigger
    /// @param  predecessor hash of the predecessor transaction
    event ScheduledTx(
        bytes32 indexed txHash,
        address to,
        uint256 value,
        bytes data,
        Enum.Operation operation,
        uint256 nonce,
        TriggerType triggerType,
        uint256 triggerTime,
        bytes32 predecessor
    );

    /// @notice CancelledTx is emitted when a transaction is cancelled
    /// @param  txHash hash of the transaction
    event CancelledTx(bytes32 indexed txHash);

    /// @notice ExecutedTx is emitted when a transaction is executed
    /// @param  txHash hash of the transaction
    event ExecutedTx(bytes32 indexed txHash);

    /// @notice SecondaryGuardSet is emitted when the secondary guard is set
    /// @param  secondaryGuard address of the secondary guard
    event SecondaryGuardSet(address secondaryGuard);

    error NotGnosisSafe();
    error TxNotPending(bytes32 txHash);
    error TooEarlyToExecute(uint256 triggerTime);
    error TxFailed(bytes32 txHash);
    error TriggerTimeTooEarly(uint256 triggerTime);
    error PredecessorNotExecuted(bytes32 predecessor, TxState state);
    error PredecessorNotPending(bytes32 predecessor, TxState state);

    /// @notice Allows the safe to set a secondary guard.
    function setSecondaryGuard(ISecondaryGuard _secondaryGuard) external;

    /// @notice Schedule a transaction. Can only be called by the safe.
    /// @param  to target address of the transaction
    /// @param  value value of the transaction
    /// @param  data data of the transaction
    /// @param  operation operation of the transaction (Call or DelegateCall)
    /// @param  triggerType type of trigger for the transaction
    /// @param  triggerTime time value for the trigger
    /// @param  predecessor hash of the predecessor transaction
    /// @return txHash hash of the transaction
    function scheduleTx(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        TriggerType triggerType,
        uint240 triggerTime,
        bytes32 predecessor
    ) external returns (bytes32);

    /// @notice Cancel a pending transaction. Can only be called by the safe.
    /// @param  txHash hash of the transaction
    function cancelTx(bytes32 txHash) external;

    /// @notice Execute a pending transaction. Can be called by anyone.
    /// @param  to target address of the transaction
    /// @param  value value of the transaction
    /// @param  data data of the transaction
    /// @param  operation operation of the transaction (Call or DelegateCall)
    /// @param  nonce nonce of the transaction (separate from the safe nonce)
    function executeTx(address to, uint256 value, bytes memory data, Enum.Operation operation, uint256 nonce)
        external;

    /// @notice The Safe that this DeadManSwitch is attached to
    function safe() external view returns (GnosisSafe);
    /// @notice Timestamp of the last standard safe transaction
    function lastInteractionTimestamp() external view returns (uint256);
    /// @notice Number of scheduled transactions created
    function scheduledTxCount() external view returns (uint256);
    /// @notice Optional secondary guard.
    ///         Since the DeadManSwitch will be set as the guard of a safe, one might wish to specify some other secondary 
    ///         guard that can check and block transactions like a normal one would.
    function secondaryGuard() external view returns (ISecondaryGuard);
    /// @notice Get information about a scheduled transaction
    function scheduledTx(bytes32 txHash) external view returns (ScheduledTxInfo memory);
    /// @notice Calculate the hash of a transaction
    function calculateTxHash(address to, uint256 value, bytes memory data, Enum.Operation operation, uint256 nonce)
        external
        pure
        returns (bytes32);
}
