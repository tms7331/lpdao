// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Address} from "v4-core/lib/openzeppelin-contracts/contracts/utils/Address.sol";
import {ERC1967Utils} from "v4-core/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "v4-core/lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";


contract CustomUpgradeableProxy is TransparentUpgradeableProxy {
    // Initialize the proxy with the implementation address, the admin, and data for the implementation's initialization
    constructor(address _logic, address admin_, bytes memory _data) TransparentUpgradeableProxy(_logic, admin_, _data) {}

    function _fallback() internal override {
        if (msg.sender == _proxyAdmin()) {
            if (msg.sig != ITransparentUpgradeableProxy.upgradeToAndCall.selector) {
                // The hook cannot make arbitrary calls, and needs to be able to call
                // checkAddLiquidity and checkSwap, so forward its calls too
                super._fallback();
            } else {
                _dispatchUpgradeToAndCallP();
            }
        } else {
            super._fallback();
        }
    }

    // Copy/pasted from TransparentUpgradeableProxy and renamed, 
    // private function and we need access in our _fallback function
    function _dispatchUpgradeToAndCallP() private {
        (address newImplementation, bytes memory data) = abi.decode(msg.data[4:], (address, bytes));
        ERC1967Utils.upgradeToAndCall(newImplementation, data);
    }
}