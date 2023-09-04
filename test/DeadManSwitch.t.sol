// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";

import "safe-contracts/GnosisSafe.sol";
import "safe-contracts/proxies/GnosisSafeProxyFactory.sol";

import "./BaseDeadManSwitchTest.t.sol";

import "../src/interfaces/IDeadManSwitch.sol";

contract DeadManSwitchTest is BaseDeadManSwitchTest {
    address etherReceiver = address(0x22);

    function setUp() public override {
        super.setUp();
        _setupSwitch();
        deadManSwitch = IDeadManSwitch(getGuard(safe));
    }

    function testProperSafeDeployment() public {
        assertEq(safe.getThreshold(), 1);
        assertEq(safe.getOwners().length, 1);
        assertEq(safe.getOwners()[0], signer);
    }

    // make sure all fields are included in hashing
    function testCalculateTxHash() public {
        bytes32 h0 = deadManSwitch.calculateTxHash(address(0), 0, new bytes(0), Enum.Operation.Call, 0);

        // change to
        bytes32 h1 = deadManSwitch.calculateTxHash(address(1), 0, new bytes(0), Enum.Operation.Call, 0);

        // change value
        bytes32 h2 = deadManSwitch.calculateTxHash(address(0), 1, new bytes(0), Enum.Operation.Call, 0);

        // change data
        bytes32 h3 = deadManSwitch.calculateTxHash(address(0), 0, new bytes(1), Enum.Operation.Call, 0);

        // change operation
        bytes32 h4 = deadManSwitch.calculateTxHash(address(0), 0, new bytes(0), Enum.Operation.DelegateCall, 0);

        // change nonce
        bytes32 h5 = deadManSwitch.calculateTxHash(address(0), 0, new bytes(0), Enum.Operation.Call, 1);

        // make sure none equal h0
        assertNotEq(h0, h1);
        assertNotEq(h0, h2);
        assertNotEq(h0, h3);
        assertNotEq(h0, h4);
        assertNotEq(h0, h5);
    }

    function testScheduleTxHappy() public {
        _scheduleTx(
            etherReceiver,
            1 ether,
            new bytes(0),
            Enum.Operation.Call,
            IDeadManSwitch.TriggerType.Timestamp,
            block.timestamp + 100,
            bytes32(0)
        );
    }

    function testAccessControl() public {
        vm.expectRevert(IDeadManSwitch.NotGnosisSafe.selector);
        deadManSwitch.scheduleTx(
            etherReceiver,
            1 ether,
            new bytes(0),
            Enum.Operation.Call,
            IDeadManSwitch.TriggerType.Timestamp,
            uint240(block.timestamp + 100),
            bytes32(0)
        );

        vm.prank(address(safe));
        bytes32 txHash = deadManSwitch.scheduleTx(
            etherReceiver,
            1 ether,
            new bytes(0),
            Enum.Operation.Call,
            IDeadManSwitch.TriggerType.Timestamp,
            uint240(block.timestamp + 100),
            bytes32(0)
        );

        vm.expectRevert(IDeadManSwitch.NotGnosisSafe.selector);
        deadManSwitch.cancelTx(txHash);

        vm.prank(address(safe));
        deadManSwitch.cancelTx(txHash);

        vm.expectRevert(IDeadManSwitch.NotGnosisSafe.selector);
        deadManSwitch.checkTransaction(
            address(0), 0, new bytes(0), Enum.Operation.Call, 0, 0, 0, address(0), payable(0), new bytes(0), address(0)
        );

        vm.prank(address(safe));
        deadManSwitch.checkTransaction(
            address(0), 0, new bytes(0), Enum.Operation.Call, 0, 0, 0, address(0), payable(0), new bytes(0), address(0)
        );
    }

    function testScheduleTxTimestampTooEarly() public {
        // make sure we cannot schedule a tx with a timestamp that is too early
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IDeadManSwitch.TriggerTimeTooEarly.selector, block.timestamp - 100));
        deadManSwitch.scheduleTx(
            etherReceiver,
            1 ether,
            new bytes(0),
            Enum.Operation.Call,
            IDeadManSwitch.TriggerType.Timestamp,
            uint240(block.timestamp - 100),
            bytes32(0)
        );
    }

    function testScheduleTxNoBogusTriggerType() public {
        // test that a bogus trigger type cannot be passed in
        vm.prank(address(safe));
        (bool success,) = address(deadManSwitch).call(
            abi.encodeWithSelector(
                deadManSwitch.scheduleTx.selector,
                etherReceiver,
                1 ether,
                new bytes(0),
                Enum.Operation.Call,
                2, // there are 2 trigger types, so 2 is invalid
                block.timestamp + 100
            )
        );

        vm.prank(address(safe));
        (bool success2,) = address(deadManSwitch).call(
            abi.encodeWithSelector(
                deadManSwitch.scheduleTx.selector,
                etherReceiver,
                1 ether,
                new bytes(0),
                Enum.Operation.Call,
                0, // there are 2 trigger types, so 0 is valid
                block.timestamp + 100
            )
        );

        assertFalse(success);
        assertTrue(success2);
    }

    function testScheduleTxBadPredecessor() public {
        bytes32 predecessor = bytes32(uint256(0x01));
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IDeadManSwitch.PredecessorNotPending.selector, predecessor, 0));
        deadManSwitch.scheduleTx(
            etherReceiver,
            1 ether,
            new bytes(0),
            Enum.Operation.Call,
            IDeadManSwitch.TriggerType.Timestamp,
            uint240(block.timestamp + 100),
            predecessor
        );
    }

    function testLastInteractionTimestampInitialValue() public {
        // make sure initial value was set properly
        assertEq(deadManSwitch.lastInteractionTimestamp(), setupTimestamp);
    }

    function testCheckTransaction() public {
        uint256 futureTimestamp = block.timestamp + 100;
        vm.warp(futureTimestamp);

        bytes memory sig = signTx(safe, pk, address(etherReceiver), 1 ether, new bytes(0), Enum.Operation.Call);

        exec(safe, etherReceiver, 1 ether, new bytes(0), Enum.Operation.Call, sig);

        // make sure lastInteractionTimestamp was updated
        assertEq(deadManSwitch.lastInteractionTimestamp(), futureTimestamp);
    }

    function testSupportsInterface() public {
        assertTrue(deadManSwitch.supportsInterface(type(IDeadManSwitch).interfaceId));
        assertTrue(deadManSwitch.supportsInterface(type(Guard).interfaceId));
        assertTrue(deadManSwitch.supportsInterface(type(IERC165).interfaceId));
    }

    function testCancelTx() public {
        // we already tested access control

        // we cannot cancel a tx that doesn't exist yet
        // assume that this test suffices for all other incorrect tx states
        bytes32 fakeTxHash = deadManSwitch.calculateTxHash(address(0), 0, new bytes(0), Enum.Operation.Call, 0);
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IDeadManSwitch.TxNotPending.selector, fakeTxHash));
        deadManSwitch.cancelTx(fakeTxHash);

        bytes32 txHash = _scheduleTx(
            etherReceiver,
            1 ether,
            new bytes(0),
            Enum.Operation.Call,
            IDeadManSwitch.TriggerType.Timestamp,
            block.timestamp + 100,
            bytes32(0)
        );

        // this function checks that the tx is in the right state afterwards
        _cancelTx(txHash);
    }

    function testExecuteHappyPath() public {
        uint256 nonce = deadManSwitch.scheduledTxCount();
        _scheduleTx(
            etherReceiver,
            1 ether,
            new bytes(0),
            Enum.Operation.Call,
            IDeadManSwitch.TriggerType.Timestamp,
            block.timestamp + 100,
            bytes32(0)
        );

        vm.warp(block.timestamp + 100);
        // this helper checks that state is set to executed
        _executeTx(etherReceiver, 1 ether, new bytes(0), Enum.Operation.Call, nonce);

        // make sure the tx actually went through
        assertEq(etherReceiver.balance, 1 ether);

        _scheduleTx(
            etherReceiver,
            1 ether,
            new bytes(0),
            Enum.Operation.Call,
            IDeadManSwitch.TriggerType.InteractionTimeout,
            100,
            bytes32(0)
        );

        vm.warp(block.timestamp + 100);
        _executeTx(etherReceiver, 1 ether, new bytes(0), Enum.Operation.Call, nonce + 1);
        assertEq(etherReceiver.balance, 2 ether);
    }

    function testExecuteNonPendingTx() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDeadManSwitch.TxNotPending.selector,
                deadManSwitch.calculateTxHash(etherReceiver, 1 ether, new bytes(0), Enum.Operation.Call, 1)
            )
        );
        deadManSwitch.executeTx(etherReceiver, 1 ether, new bytes(0), Enum.Operation.Call, 1);
    }

    function testExecuteTooEarly() public {
        uint256 initialTs = block.timestamp;
        uint256 initialNonce = deadManSwitch.scheduledTxCount();

        _scheduleTx(
            etherReceiver,
            1 ether,
            new bytes(0),
            Enum.Operation.Call,
            IDeadManSwitch.TriggerType.Timestamp,
            initialTs + 100,
            bytes32(0)
        );

        _scheduleTx(
            etherReceiver,
            1 ether,
            new bytes(0),
            Enum.Operation.Call,
            IDeadManSwitch.TriggerType.InteractionTimeout,
            1000,
            bytes32(0)
        );

        vm.warp(initialTs + 99);
        vm.expectRevert(abi.encodeWithSelector(IDeadManSwitch.TooEarlyToExecute.selector, initialTs + 100));
        deadManSwitch.executeTx(etherReceiver, 1 ether, new bytes(0), Enum.Operation.Call, initialNonce);

        // should go through now
        vm.warp(initialTs + 100);
        deadManSwitch.executeTx(etherReceiver, 1 ether, new bytes(0), Enum.Operation.Call, initialNonce);

        // module txs do not update lastInteractionTimestamp because they don't go through the guard

        // execute a tx to update lastInteractionTimestamp
        uint256 expectedLastInteractionTimestamp = block.timestamp;
        signAndExec(safe, pk, address(etherReceiver), 1 ether, new bytes(0), Enum.Operation.Call);

        // quick sanity check
        assertEq(deadManSwitch.lastInteractionTimestamp(), expectedLastInteractionTimestamp);

        vm.warp(expectedLastInteractionTimestamp + 999);
        vm.expectRevert(
            abi.encodeWithSelector(IDeadManSwitch.TooEarlyToExecute.selector, expectedLastInteractionTimestamp + 1000)
        );
        deadManSwitch.executeTx(etherReceiver, 1 ether, new bytes(0), Enum.Operation.Call, initialNonce + 1);

        // should go through now
        vm.warp(expectedLastInteractionTimestamp + 1000);
        deadManSwitch.executeTx(etherReceiver, 1 ether, new bytes(0), Enum.Operation.Call, initialNonce + 1);
    }

    function testExecuteFailingTx() public {
        // try to schedule and execute a tx that sends too much ether
        uint256 nonce = deadManSwitch.scheduledTxCount();
        bytes32 txHash = _scheduleTx(
            etherReceiver,
            101 ether, // safe's balance is 100 ether
            new bytes(0),
            Enum.Operation.Call,
            IDeadManSwitch.TriggerType.Timestamp,
            block.timestamp + 100,
            bytes32(0)
        );

        vm.warp(block.timestamp + 100);
        vm.expectRevert(abi.encodeWithSelector(IDeadManSwitch.TxFailed.selector, txHash));
        deadManSwitch.executeTx(etherReceiver, 101 ether, new bytes(0), Enum.Operation.Call, nonce);
    }

    function testExecuteWithNonExecutedPredecessor() public {
        bytes32 predecessor = _scheduleTx(
            etherReceiver,
            1 ether,
            new bytes(0),
            Enum.Operation.Call,
            IDeadManSwitch.TriggerType.Timestamp,
            block.timestamp + 100,
            bytes32(0)
        );

        _scheduleTx(
            etherReceiver,
            1 ether,
            new bytes(0),
            Enum.Operation.Call,
            IDeadManSwitch.TriggerType.Timestamp,
            block.timestamp + 100,
            predecessor
        );

        vm.warp(block.timestamp + 100);
        vm.expectRevert(abi.encodeWithSelector(IDeadManSwitch.PredecessorNotExecuted.selector, predecessor, 1));
        deadManSwitch.executeTx(etherReceiver, 1 ether, new bytes(0), Enum.Operation.Call, 1);
    }

    // todo: test secondary guard
}
