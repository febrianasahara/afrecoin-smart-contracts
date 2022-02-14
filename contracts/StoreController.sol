// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.11;
 
import "@openzeppelin/contracts/access/Ownable.sol"; 
import "@openzeppelin/contracts/utils/Strings.sol";

contract StoreController is Ownable { 
    using Strings for uint;
    struct Product {
        uint256 id;
        string name;
        string imageUrl; 
        uint256 price;  // amount to transfer
        string symbol;  // i.e BWPT | TZAR | TKES | NGTX | | UGXT | 
        address pricipleContract;
        address soldBy;
        uint256 createdAt;
        bool published; 
    }
    
     struct Category {
        uint256 id; 
        uint32 productId;

    }

    struct Receipt {
        uint256 id; 
        uint32 categoryId;
        uint32 productId;
        address seller;
        address buyer;
        uint256 timestamp;
    }
    
    /* EVENTS */
    event InventoryQuantityChanged(address seller, uint32 to, uint32 from,uint256 productId, uint32 change, uint256 timestamp);
     //products
    event ProductAdded(address seller, uint256 productId,uint256 categoryId, uint32 qty, uint32 discount);
    event ProductRemoved(bool completed);
    event ProductSold(address seller, address buyer,uint256 categoryId, uint256 productId,uint32 quantityLeft );
    event DiscountApplied(address seller,uint256 categoryId, uint256 productId, uint32 currentDiscount, uint256 timestamp);


    Product p; // variable to 
   
    mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => Product)))) _products; // map of all products
    mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => uint32)))) _quantities; // map of all product quantities
    mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => uint32)))) _discounts; // map of all product discounts percentages
 
     function addProduct( 
        string calldata _productName, 
        uint256  _category,
        string calldata _url,  
        uint256  _price,
        string calldata _sym,
        uint32  _qty,
        uint32  _discount,
        address _contract,
        address _soldBy) public onlyOwner returns(uint256,uint32,uint32) { // returns product id
        uint256 _i = block.timestamp;
        p =  Product({
        id:_i,
        soldBy: _soldBy,
        name:_productName,
        imageUrl: _url, 
        symbol: _sym,
        createdAt: block.timestamp,
        published: true,
        price:_price,
        pricipleContract:_contract  });
        // add new product 
        _products[_msgSender()][_soldBy][_category][_i] = p;
        _quantities[_msgSender()][_soldBy][_category][_i] = _qty;
         _discounts[_msgSender()][_soldBy][_category][_i] = _discount;
        // add the product to the list of indexes
        return (block.timestamp,_qty,_discount);
     }

     function removeProduct(address _seller, uint256  _categoryId, uint256  _prodId) public onlyOwner returns(bool){
        _products[_msgSender()][_seller][_categoryId][_prodId].published = false; //soft delete for Comliance
        _quantities[_msgSender()][_seller][_categoryId][_prodId] = 0;
        _discounts[_msgSender()][_seller][_categoryId][_prodId] = 0;
        return true;
     }
     

       function _applyDiscount(address _seller, uint256  _categoryId, uint256 _prodId, uint32  _discount) internal  onlyOwner returns(bool){
            _discounts[_msgSender()][_seller][_categoryId][_prodId] = _discount;
         return true;
     }

    function _applyQuantity(address _seller, uint256  _categoryId, uint256  _prodId, uint32  _qty) internal  onlyOwner returns(bool){
        _quantities[_msgSender()][_seller][_categoryId][_prodId] = _qty;
        return true;
    }

    function _decreaseInventory(address _seller, uint256  _categoryId, uint256  _prodId, uint32  _qtySold) internal  onlyOwner returns(bool){
        _quantities[_msgSender()][_seller][_categoryId][_prodId] = _quantities[_msgSender()][_seller][_categoryId][_prodId] - _qtySold;
        return true;
     }

    function _increaseInventory(address _seller,  uint256 _categoryId, uint256  _prodId, uint32  _qtyRestored) internal  onlyOwner returns(bool){
        _quantities[_msgSender()][_seller][_categoryId][_prodId]==_quantities[_msgSender()][_seller][_categoryId][_prodId] + _qtyRestored;
        return true;
     }


     
     
 

    

    // calculate share of pool


    

}
