// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";

import "safe-contracts/GnosisSafe.sol";
import "safe-contracts/proxies/GnosisSafeProxyFactory.sol";

import "./GnosisHelper.sol";
import "../src/DeadManSwitchFactory.sol";
import "../src/DeadManSwitch.sol";

contract BaseDeadManSwitchTest is Test, GnosisHelper {
    uint256 pk = 1;
    address signer = vm.addr(pk);

    GnosisSafe safe;
    DeadManSwitchFactory factory;
    IDeadManSwitch deadManSwitch;

    uint256 setupTimestamp;

    function setUp() public virtual {
        setupTimestamp = block.timestamp;

        address[] memory owners = new address[](1);
        owners[0] = signer;

        safe = GnosisSafe(createSafe(owners, 1, 982374598237497));
        factory = new DeadManSwitchFactory();

        assertEq(getGuard(safe), address(0));

        vm.deal(address(safe), 100 ether);
    }

    function _addModule(address mod) public {
        bool success = signAndExec(
            safe, pk, address(safe), 0, abi.encodeWithSelector(safe.enableModule.selector, mod), Enum.Operation.Call
        );

        // assert that the call succeeded
        assertTrue(success);

        // assert that it is set as a module as well
        assertTrue(safe.isModuleEnabled(mod));
    }

    function _setupSwitch() internal {
        bool success = signAndExec(
            safe,
            pk,
            address(factory),
            0,
            abi.encodeWithSelector(DeadManSwitchFactory.setup.selector),
            Enum.Operation.DelegateCall
        );

        // assert that the call succeeded
        assertTrue(success);

        // assert that the guard is set
        address newSwitch = getGuard(safe);
        assertTrue(newSwitch != address(0));

        // assert that it is set as a module as well
        assertTrue(safe.isModuleEnabled(newSwitch));

        // assert that the new contract is an IDeadManSwitch
        deadManSwitch = IDeadManSwitch(newSwitch);
        assertTrue(deadManSwitch.supportsInterface(type(IDeadManSwitch).interfaceId));
    }

    function _teardownSwitch() internal {
        address prevGuard = getGuard(safe);
        assertTrue(prevGuard != address(0));

        bool success = signAndExec(
            safe,
            pk,
            address(factory),
            0,
            abi.encodeWithSelector(DeadManSwitchFactory.teardown.selector, address(0)),
            Enum.Operation.DelegateCall
        );

        assertTrue(success);
        assertTrue(getGuard(safe) == address(0));
        assertFalse(safe.isModuleEnabled(prevGuard));
    }

    function _scheduleTx(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        IDeadManSwitch.TriggerType triggerType,
        uint256 triggerTime,
        bytes32 predecessor
    ) internal returns (bytes32) {
        uint256 nonce = deadManSwitch.scheduledTxCount();
        bool success = signAndExec(
            safe,
            pk,
            address(deadManSwitch),
            0,
            abi.encodeWithSelector(
                IDeadManSwitch.scheduleTx.selector, to, value, data, operation, triggerType, triggerTime, predecessor
            ),
            Enum.Operation.Call
        );

        assertTrue(success);

        bytes32 txHash = deadManSwitch.calculateTxHash(to, value, data, operation, nonce);

        IDeadManSwitch.ScheduledTxInfo memory scheduledTx = deadManSwitch.scheduledTx(txHash);
        assertTrue(scheduledTx.state == IDeadManSwitch.TxState.Pending);
        assertTrue(scheduledTx.triggerType == triggerType);
        assertTrue(scheduledTx.triggerTime == triggerTime);

        return txHash;
    }

    function _cancelTx(bytes32 txHash) internal {
        bool success = signAndExec(
            safe,
            pk,
            address(deadManSwitch),
            0,
            abi.encodeWithSelector(IDeadManSwitch.cancelTx.selector, txHash),
            Enum.Operation.Call
        );

        assertTrue(success);

        IDeadManSwitch.ScheduledTxInfo memory scheduledTx = deadManSwitch.scheduledTx(txHash);
        assertTrue(scheduledTx.state == IDeadManSwitch.TxState.Cancelled);
    }

    function _executeTx(address to, uint256 value, bytes memory data, Enum.Operation operation, uint256 nonce)
        internal
    {
        bytes32 txHash = deadManSwitch.calculateTxHash(to, value, data, operation, nonce);
        deadManSwitch.executeTx(to, value, data, operation, nonce);
        assertTrue(deadManSwitch.scheduledTx(txHash).state == IDeadManSwitch.TxState.Executed);
    }
}
