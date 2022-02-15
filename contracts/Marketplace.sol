// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.11;
 
import "@openzeppelin/contracts/access/Ownable.sol"; 
import "@openzeppelin/contracts/utils/Strings.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/* TODO : Add/Update/Remove Stores + Create Receipt  */

contract Marketplace is Ownable { 
    using SafeMath for uint256;
     using SafeMath for uint32;
    using Strings for uint;
    struct Product {
        uint256 id;
        string name;
        string imageUrl; 
        uint256 price;  // amount to transfer 
        address pricipleContract;
        address soldBy;
        string desc;
        bool published; 
    }
    
     struct Category {
        uint256 id; 
        string name;
        string isleName;

    }

    struct Receipt {
        uint256 id; 
        mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => mapping(uint => uint))))) lineItems;
        uint256 lineTotal; 
        address buyer; 
        string status;
    }
      struct StoreFront {
        uint256 id;
        string name;
        string shortCode; 
    }
    /* EVENTS */
    event InventoryQuantityChanged(address s, uint t, uint f,uint256 prdId, uint diff, uint256 dt);
     // basic product management
    event CategoryAdded(address s, Category c);
    event CategoryUpdated(address s, Category c);
    
    event NewProductAdded(address seller, Product product);
    event ProductRemoved(bool completed);
     
    event DiscountApplied(address sender,Product product, uint32 discount, uint256 date);
    event ProductFetch(Product product, uint256 timestamp); //public 
    event GetCategorysProduct(Product products, uint256 timestamp); //public  
    event StoreRetrieved(StoreFront store); //public   
    event AddedToCart(Product[] updatedCart); //public   
    event CartCleared(); //public    


    Product p; // variable to 
    Category c; 
    Product[] currentCart;
    int private productCount = 0;
    mapping(address => mapping(address =>  mapping(uint256 => StoreFront))) _stores;
    mapping(address => mapping(address =>  mapping(uint256 => Category))) _categories;
    mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => Product)))) _products; // map of all products
    mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => uint)))) _quantities; // map of all product quantities
    mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => uint32)))) _discounts; // map of all product discounts percentages
 
    // cart logic   sender // buyer // category // productId // price (less discounts) //
     mapping(address => mapping(address => mapping(string => Product[]))) _cart; //with quanities
     
     function addProduct( 
        string calldata _productName, 
        uint256  _category,
        string calldata _url,  
        uint256  _price,
        string calldata _desc,
        uint32  _qty, 
        address _soldBy) public onlyOwner returns(bool) { // returns product id
        uint256 _i = block.timestamp;
        p =  Product({
        id:_i,
        soldBy: _soldBy,
        name:_productName,
        imageUrl: _url, 
        desc: _desc,
        published: true,
        price:_price,
        pricipleContract:owner() });
        // add new product 
        _products[_msgSender()][_soldBy][_category][_i] = p;
        _quantities[_msgSender()][_soldBy][_category][_i] = _qty;
         _discounts[_msgSender()][_soldBy][_category][_i] = 0;
        // add the product to the list of indexes

        emit NewProductAdded( _soldBy,p);
        return true;
     }

        function addCategory( address seller,
        string calldata _categoryName,string calldata _islename  ) public onlyOwner returns(bool) { // returns product id
        uint256 _i = block.timestamp;
        c =  Category({
        id:_i,
        name:_categoryName,isleName: _islename  });
        // add new product 
        _categories[_msgSender()][seller][_i] = c;  

        emit CategoryAdded( seller, c);
        return true;
     }

     function removeProduct(address _seller, uint256  _categoryId, uint256  _prodId) public onlyOwner returns(bool){
        _products[_msgSender()][_seller][_categoryId][_prodId].published = false; //soft delete for Comliance
        _quantities[_msgSender()][_seller][_categoryId][_prodId] = 0;
        _discounts[_msgSender()][_seller][_categoryId][_prodId] = 0;
        emit ProductRemoved(true);
        return true;
     }
     

       function _applyDiscount(address _seller, uint256  _categoryId, uint256 _prodId, uint32  _discount)  external  onlyOwner returns(bool){
            _discounts[_msgSender()][_seller][_categoryId][_prodId] = _discount;
         return true;
     }

    function _applyQuantity(address _seller, uint256  _categoryId, uint256  _prodId, uint  _qty)  external  onlyOwner returns(bool){
        _quantities[_msgSender()][_seller][_categoryId][_prodId] = _qty;
        return true;
    }

    function _decreaseInventory(address _seller, uint256  _categoryId, uint256  _prodId, uint  _qtySold)  external   onlyOwner  {
        uint256 oldAmount = _quantities[_msgSender()][_seller][_categoryId][_prodId];
        uint256 newAmount =  oldAmount.sub(_quantities[_msgSender()][_seller][_categoryId][_prodId]);
       uint256 change = oldAmount.sub(newAmount);
     
        _quantities[_msgSender()][_seller][_categoryId][_prodId] = _quantities[_msgSender()][_seller][_categoryId][_prodId] - _qtySold;
        emit InventoryQuantityChanged(_seller, newAmount, oldAmount, _prodId, change, block.timestamp);
     }


     function _increaseInventory(address _seller,  uint256 _categoryId, uint256  _prodId, uint32  _qtyRestored) external onlyOwner   {
          uint256 oldAmount = _quantities[_msgSender()][_seller][_categoryId][_prodId];
        uint256 newAmount =  oldAmount.add(_quantities[_msgSender()][_seller][_categoryId][_prodId]);
      
        _quantities[_msgSender()][_seller][_categoryId][_prodId]==_quantities[_msgSender()][_seller][_categoryId][_prodId] + _qtyRestored;
         emit InventoryQuantityChanged(_seller, oldAmount, newAmount, _prodId, newAmount.sub(oldAmount), block.timestamp);

     }
    
    
    
    function GetProductByIdAsync(address _seller,  uint256 _categoryId, uint256  _prodId) public  {
        Product storage p =_products[_msgSender()][_seller][_categoryId][_prodId];
        emit  ProductFetch(p , block.timestamp);

    }
  function addToCart(address _buyer,address _seller, string calldata _sessionId, uint256 _categoryId, uint256  _prodId, uint qty) public onlyOwner   {
        currentCart= _cart[_msgSender()][_buyer][_sessionId];
        currentCart.push(_products[_msgSender()][_seller][_categoryId][_prodId]);
        _cart[_seller][_buyer][_sessionId] = currentCart; 
        emit  AddedToCart(currentCart);
}

    function clearCart(address buyer, address seller, string calldata session) public onlyOwner returns(bool){
        delete  _cart[seller][buyer][session];
        emit CartCleared();
        return true;
    }



   
}
     
