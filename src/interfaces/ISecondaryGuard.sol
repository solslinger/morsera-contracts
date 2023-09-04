// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {Enum} from "safe-contracts/GnosisSafe.sol";

/// @title  ISecondaryGuard
/// @notice Interface for a secondary guard that can be added to a DeadManSwitch
/// @dev    This interface is the same as the standard Guard interface, but with an extra `safe` parameter on both functions.
///         This is needed because other guards assume that the `safe` is the msg.sender, but in the case of a DeadManSwitch,
///         the msg.sender is the DeadManSwitch itself.
interface ISecondaryGuard {
    function checkTransaction(
        address safe,
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
    ) external;

    function checkAfterExecution(address safe, bytes32 txHash, bool success) external;
}
