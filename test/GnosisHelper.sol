// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";

import {GnosisSafe, Enum} from "safe-contracts/GnosisSafe.sol";
import {GnosisSafeProxyFactory} from "safe-contracts/proxies/GnosisSafeProxyFactory.sol";

abstract contract GnosisHelper is Test {
    address constant safeSingleton = 0x3E5c63644E683549055b9Be8653de26E0B4CD36E;
    address constant fallbackHandler = 0xf48f2B2d2a534e402487b3ee7C18c33Aec0Fe5e4;
    GnosisSafeProxyFactory constant safeFactory = GnosisSafeProxyFactory(0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2);

    bytes32 internal constant GUARD_STORAGE_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;

    function createSafe(address[] memory owners, uint256 threshold, uint256 nonce) internal returns (GnosisSafe) {
        return GnosisSafe(
            payable(
                address(
                    safeFactory.createProxyWithNonce(
                        safeSingleton,
                        abi.encodeWithSignature(
                            "setup(address[],uint256,address,bytes,address,address,uint256,address)",
                            owners,
                            threshold,
                            address(0),
                            "0x",
                            fallbackHandler,
                            address(0),
                            0,
                            address(0)
                        ),
                        nonce
                    )
                )
            )
        );
    }

    function signTx(GnosisSafe safe, uint256 pk, address to, uint256 value, bytes memory data, Enum.Operation operation)
        internal
        view
        returns (bytes memory)
    {
        uint256 nonce = safe.nonce();
        bytes32 txHash =
            keccak256(safe.encodeTransactionData(to, value, data, operation, 0, 0, 0, payable(0), payable(0), nonce));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, txHash);

        return abi.encodePacked(r, s, v);
    }

    function signAndExec(
        GnosisSafe safe,
        uint256 pk,
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) internal returns (bool) {
        bytes memory sig = signTx(safe, pk, to, value, data, operation);
        return exec(safe, to, value, data, operation, sig);
    }

    function exec(
        GnosisSafe safe,
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        bytes memory sigs
    ) internal returns (bool) {
        return safe.execTransaction(to, value, data, operation, 0, 0, 0, payable(0), payable(0), sigs);
    }

    function getGuard(GnosisSafe safe) internal view returns (address) {
        return address(uint160(uint256(vm.load(address(safe), GUARD_STORAGE_SLOT))));
    }
}
