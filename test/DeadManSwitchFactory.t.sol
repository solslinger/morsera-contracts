// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";

import "safe-contracts/GnosisSafe.sol";
import "safe-contracts/proxies/GnosisSafeProxyFactory.sol";

import "./BaseDeadManSwitchTest.t.sol";
import "../src/DeadManSwitchFactory.sol";
import "../src/DeadManSwitch.sol";

contract DeadManSwitchFactoryTest is BaseDeadManSwitchTest {
    function testOnlyDelegateCall() public {
        vm.expectRevert(OnlyDelegateCall.NotDelegateCall.selector);
        vm.prank(address(safe));
        factory.setup();
    }

    function testSetup() public {
        _setupSwitch();
    }

    function testCannotSetupWithNonZeroGuard() public {
        _setupSwitch();

        bytes memory sig = signTx(
            safe,
            pk,
            address(factory),
            0,
            abi.encodeWithSelector(DeadManSwitchFactory.setup.selector),
            Enum.Operation.DelegateCall
        );

        vm.expectRevert("GS013");
        exec(
            safe,
            address(factory),
            0,
            abi.encodeWithSelector(DeadManSwitchFactory.setup.selector),
            Enum.Operation.DelegateCall,
            sig
        );
    }

    function testTeardown() public {
        _setupSwitch();
        _teardownSwitch();
    }

    function testTeardownWithMultipleModules() public {
        _addModule(address(0x1100));
        _addModule(address(0x2200));

        _setupSwitch();

        _addModule(address(0x3300));

        _teardownSwitch();

        assertTrue(safe.isModuleEnabled(address(0x1100)));
        assertTrue(safe.isModuleEnabled(address(0x2200)));
        assertTrue(safe.isModuleEnabled(address(0x3300)));
    }
}
