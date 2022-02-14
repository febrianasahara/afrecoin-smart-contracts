pragma solidity ^0.8.11;

import "../ERC20.sol";
import "../Stakeable.sol";

contract TokenV1 is ERC20, Stakeable {
    string private _tokenName = "TokenV1";
    string private _symbol = "TVT";
    uint8 private _decimals = 18;
    uint256 private decimalFactor = 10**_decimals;
    uint256 private totalTokenSupply = 10**8 * decimalFactor;

    constructor() public payable {
        // set tokenOwnerAddress as owner of all tokens

        _mint(msg.sender, totalTokenSupply);
        tokenAddress = payable(msg.sender); 
    }

    /**
     * @dev Burns a specific amount of tokens.
     * @param value The amount of lowest token units to be burned.
     */
    function burn(uint256 value) public {
        _burn(msg.sender, value);
    }

    // optional functions from ERC20 stardard

    /**
     * @return the name of the token.
     */
    function name() public view returns (string memory) {
        return _tokenName;
    }

    /**
     * @return the symbol of the token.
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
     * @return the number of decimals of the token.
     */
    function decimals() public view returns (uint8) {
        return _decimals;
    }
}
