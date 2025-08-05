// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title Initializable
 * @dev Base contract for proxy-compatible initialization
 * This contract ensures that initialization can only happen once
 */
abstract contract Initializable {
    bool private _initialized;
    bool private _initializing;

    event Initialized(uint8 version);

    modifier initializer() {
        bool isTopLevelCall = !_initializing;
        require(
            (isTopLevelCall && !_initialized) || (!isTopLevelCall && _initialized),
            "Initializable: contract is already initialized"
        );

        bool isFirstInitCall = isTopLevelCall && !_initialized;
        if (isFirstInitCall) {
            _initialized = true;
            _initializing = true;
        }

        _;

        if (isFirstInitCall) {
            _initializing = false;
            emit Initialized(1);
        }
    }

    modifier reinitializer(uint8 version) {
        require(!_initializing && _initialized, "Initializable: contract is not initialized");
        require(version > 1, "Initializable: version must be greater than 1");

        _initializing = true;
        _;
        _initializing = false;

        emit Initialized(version);
    }

    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    function _disableInitializers() internal virtual {
        require(!_initializing, "Initializable: contract is initializing");
        if (!_initialized) {
            _initialized = true;
            emit Initialized(type(uint8).max);
        }
    }

    function _getInitializedVersion() internal view returns (uint8) {
        return _initialized ? 1 : 0;
    }

    function _isInitializing() internal view returns (bool) {
        return _initializing;
    }
}
