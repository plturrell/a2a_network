// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Pausable
 * @dev Contract module which allows children to implement an emergency stop mechanism
 * that can be triggered by an authorized account.
 */
abstract contract Pausable is AccessControl {
    bool private _paused;
    address public pauser;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    event Paused(address account);
    event Unpaused(address account);
    event PauserChanged(address indexed previousPauser, address indexed newPauser);

    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }

    modifier onlyPauser() {
        require(hasRole(PAUSER_ROLE, msg.sender), "Pausable: caller is not the pauser");
        require(msg.sender == pauser, "Pausable: caller is not the pauser");
        _;
    }

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _paused = false;
        pauser = msg.sender;
    }

    function paused() public view returns (bool) {
        return _paused;
    }

    function pause() external onlyPauser whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyPauser whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }

    function changePauser(address newPauser) external onlyPauser {
        require(newPauser != address(0), "Pausable: new pauser is the zero address");
        // Revoke role from current pauser and assign to new
        revokeRole(PAUSER_ROLE, pauser);
        grantRole(PAUSER_ROLE, newPauser);
        require(newPauser != address(0), "Pausable: new pauser is the zero address");
        address oldPauser = pauser;
        pauser = newPauser;
        emit PauserChanged(oldPauser, newPauser);
    }

    // Storage gap for future upgrades
    uint256[50] private __gap;

}