// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.11;
 
import "@openzeppelin/contracts/access/Ownable.sol"; 

contract PartnerController is Ownable { 

    struct ProjectPartner {
        string country;
        uint256 createdAt; 
    }

    mapping(address => ProjectPartner) private partners;
    mapping(address => bool) private _isPartner; 

     function addProjectPartner(string memory country_,address _partner) public onlyOwner {
         
        partners[_partner] =  ProjectPartner({country:country_, createdAt: block.timestamp});
        _isPartner[_partner] = true;
     }

     function removeProjectPartner(address partner) public onlyOwner {
         delete partners[partner];
         delete _isPartner[partner];
    }
    function isPartner(address user) public view returns(bool result)  {
         return _isPartner[user];
    }
    

    // calculate share of pool


    

}
