// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";

import {OnlyDelegateCall} from "../src/OnlyDelegateCall.sol";

contract Concrete is OnlyDelegateCall {
    function foo() external view onlyDelegateCall returns (uint256) {
        return 1;
    }

    fallback() external onlyDelegateCall {}
}

contract OnlyDelegateCallTest is Test {
    Concrete concrete;

    function setUp() public {
        concrete = new Concrete();
    }

    function testOnlyDelegateCall() public {
        vm.expectRevert(OnlyDelegateCall.NotDelegateCall.selector);
        concrete.foo();

        address _concrete = address(concrete);

        uint256 success;
        assembly {
            success := delegatecall(gas(), _concrete, 0, 0, 0, 0)
        }

        assertEq(success, 1);
    }
}
