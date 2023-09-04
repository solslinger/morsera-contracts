// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {OnlyDelegateCall} from "./OnlyDelegateCall.sol";
import {DeadManSwitch} from "./DeadManSwitch.sol";
import {IDeadManSwitch} from "./interfaces/IDeadManSwitch.sol";
import {GnosisSafe} from "safe-contracts/GnosisSafe.sol";

/// @title DeadManSwitchFactory
/// @notice Deploys, sets up, and tears down DeadManSwitch contracts via delegate call from a safe.
contract DeadManSwitchFactory is GnosisSafe, OnlyDelegateCall {
    event SetupDeadManSwitch(address deadManSwitch);
    event ToreDownDeadManSwitch(address deadManSwitch);

    error GuardAlreadySet(address guard);
    error GuardNotDeadManSwitch(address guard);
    error ModuleNotFound();
    error MismatchedVersion();

    /// @dev Makes sure that the calling safe is the expected version
    modifier onlyMatchingVersion() {
        bytes32 safeVersionHash = keccak256(bytes(GnosisSafe(payable(address(this))).VERSION()));
        bytes32 thisVersionHash = keccak256(bytes(VERSION));
        if (safeVersionHash != thisVersionHash) {
            revert MismatchedVersion();
        }
        _;
    }

    /// @notice Set up a new DeadManSwitch. Can only be delegate called by a gnosis safe of matching version.
    ///         Will revert if a guard is already set on the safe.
    /// @dev    Deploys a new DeadManSwitch, enables it as a module, and sets it as the safe's guard.
    function setup() external onlyDelegateCall onlyMatchingVersion {
        GnosisSafe safe = GnosisSafe(payable(address(this)));
        address oldGuard = getGuard();

        if (oldGuard != address(0)) {
            revert GuardAlreadySet(oldGuard);
        }

        DeadManSwitch dms = new DeadManSwitch(safe);
        safe.enableModule(address(dms));
        safe.setGuard(address(dms));
        emit SetupDeadManSwitch(address(dms));
    }

    /// @notice Tear down an existing DeadManSwitch. Can only be delegate called by a gnosis safe of matching version.
    ///         Removes the DeadManSwitch as a module and sets guard to 0x00.
    /// @param  prevModule Address of previous module in linked list, if set to 0, then the list will be searched.
    function teardown(address prevModule) external onlyDelegateCall onlyMatchingVersion {
        address guard = getGuard();

        require(guard != address(0), "guard not set");

        // require that the guard is a DeadManSwitch
        if (!IDeadManSwitch(guard).supportsInterface(type(IDeadManSwitch).interfaceId)) {
            revert GuardNotDeadManSwitch(guard);
        }

        // unset the guard
        GnosisSafe safe = GnosisSafe(payable(address(this)));
        safe.setGuard(address(0));

        // disable the module
        if (prevModule == address(0)) {
            prevModule = findPrevModule(guard);
        }
        safe.disableModule(prevModule, guard);

        emit ToreDownDeadManSwitch(guard);
    }

    /// @dev Search through the linked list of modules to find the one before `module`
    function findPrevModule(address module) internal view returns (address) {
        address thisModule = SENTINEL_MODULES;

        do {
            address nextModule = modules[thisModule];
            if (nextModule == module) {
                return thisModule;
            }
            thisModule = nextModule;
        } while (thisModule != SENTINEL_MODULES);

        revert ModuleNotFound();
    }
}
