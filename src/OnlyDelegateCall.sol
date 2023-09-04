// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

/// @title OnlyDelegateCall
/// @notice Contains a helper modifier to make sure functions are being delegate called
abstract contract OnlyDelegateCall {
    address private immutable _this;

    error NotDelegateCall();

    constructor() {
        _this = address(this);
    }

    modifier onlyDelegateCall() {
        if (_this == address(this)) revert NotDelegateCall();
        _;
    }
}
