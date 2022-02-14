pragma solidity ^0.8.11;

import "./StoreController.sol";
import "./PartnerController.sol";

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract BWPT is StoreController {
    /**
     * MATH
         0000000000000000000
     */

    using SafeMath for uint256;
    using Address for address;
   
    /**
     * DATA
     */

    // INITIALIZATION DATA
    bool private initialized = false;
    bytes32 r1;
    // ERC20 BASIC DATA
    mapping(address => uint256) internal balances;
    uint256 internal totalSupply_;
 

    /* IMPORTANT - REQUIRED */
    address payable private  _GaziniContract; // FEE TOKEN
    string public constant name = "Fiat-Peg Botswana Pula Token (BWPT)"; // solium-disable-line
    string public constant symbol = "BWPT"; // solium-disable-line uppercase

    //  optional ERC20 fees paid to the delegate of betaDelegatedTransfer by the from address.
    uint8 public transferFee = 3; // 50% fee is swapped into Gazini and sent to rewards wallet
    uint8 public constant decimals = 18; // solium-disable-line uppercase
    uint256 private decimalFactor = 10**decimals;
    uint256 private transactionDeadline = 50; // a block number after which the pre-signed transaction has expired.
    mapping(address => bool) private _isExcludedFromFee;
     
    // ERC20 DATA
    mapping(address => mapping(address => uint256)) internal allowed;

    // OWNER DATA PART 1
    address public _owner;

    // PAUSABILITY DATA
    bool public paused = false;

    // ASSET PROTECTION DATA
    address public assetProtectionRole;
    mapping(address => bool) internal frozen;

    // SUPPLY CONTROL DATA
    address public supplyController;

    // OWNER DATA PART 2
    address public proposedOwner;

    // DELEGATED TRANSFER DATA
    address public betaDelegateWhitelister;
    mapping(address => bool) internal betaDelegateWhitelist;
    mapping(address => uint256) internal nextSeqs;
    // EIP191 header for EIP712 prefix
    string internal constant EIP191_HEADER = "\x19\x01";
    // Hash of the EIP712 Domain Separator Schema
    bytes32 internal constant EIP712_DOMAIN_SEPARATOR_SCHEMA_HASH =
        keccak256("EIP712Domain(string name,address verifyingContract)");
    bytes32 internal constant EIP712_DELEGATED_TRANSFER_SCHEMA_HASH =
        keccak256(
            "BetaDelegatedTransfer(address to,uint256 value,uint256 fee,uint256 seq,uint256 deadline)"
        );
    // Hash of the EIP712 Domain Separator data
    // solhint-disable-next-line var-name-mixedcase
    bytes32 public EIP712_DOMAIN_HASH;

    /* LIQUIDITY POOLS */
    IUniswapV2Router02 public uniswapV2Router;
     /* Ripple (XRP) */
    address private _xrpPair; // XRP Liquidity pool
    address payable internal  _xrpContract; 

     /* Ripple (XRP) */
    address private _bnbPair; // BNB Liquidity pool address
    address payable internal  _bnbContract; 

    address private _usdtPair; // USDT Liquidity pool
    address payable internal  _usdtContract; 

    /* Binance-Peg Stellar Token (XLM) */
    address private _xlmPair; // XLM Liquidity pool
    address payable internal  _xlmContract; 

    /* Binance-Peg Stellar Token (USDC) */
    address private _usdcPair; // XLM Liquidity pool
    address payable internal  _usdcContract; 

    uint256 private _liqAmount; // how much liquidity fees to take
    /* OperationalWallets */
    bool takeFeesMutexLock;

    /* Operational  wallet */
        address payable constant _feeAddress =
        payable(0x30FBf4dFE1df1e951A1eBC7A1439Fcf2af45b79f); 

    /**
     * EVENTS
     */

    // ERC20 BASIC EVENTS
    event Transfer(address indexed from, address indexed to, uint256 value);

    // ERC20 EVENTS
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    // OWNABLE EVENTS
    event OwnershipTransferProposed(
        address indexed currentOwner,
        address indexed proposedOwner
    );
    event OwnershipTransferDisregarded(address indexed oldProposedOwner);
    // event OwnershipTransferred(
    //     address indexed oldOwner,
    //     address indexed newOwner
    // );

    // PAUSABLE EVENTS
    event Pause();
    event Unpause();

    // ASSET PROTECTION EVENTS
    event AddressFrozen(address indexed addr);
    event AddressUnfrozen(address indexed addr);
    event FrozenAddressWiped(address indexed addr);
    event AssetProtectionRoleSet(
        address indexed oldAssetProtectionRole,
        address indexed newAssetProtectionRole
    );

    // SUPPLY CONTROL EVENTS
    event SupplyIncreased(address indexed to, uint256 value);
    event SupplyDecreased(address indexed from, uint256 value);
    event SupplyControllerSet(
        address indexed oldSupplyController,
        address indexed newSupplyController
    );

    // DELEGATED TRANSFER EVENTS
    event BetaDelegatedTransfer(
        address indexed from,
        address indexed to,
        uint256 value,
        uint256 seq,
        uint256 fee
    );
    event BetaDelegateWhitelisterSet(
        address indexed oldWhitelister,
        address indexed newWhitelister
    );
    event BetaDelegateWhitelisted(address indexed newDelegate);
    event BetaDelegateUnwhitelisted(address indexed oldDelegate);

    /**
     * FUNCTIONALITY
     */

    // INITIALIZATION FUNCTIONALITY

    /**
     * @dev sets 0 initials tokens, the owner, and the supplyController.
     * this serves as the constructor for the proxy but compiles to the
     * memory model of the Implementation contract.
     */
    function initialize() public {
        require(!initialized, "already initialized");
        _owner = msg.sender;
        assetProtectionRole = address(0);
        totalSupply_ = 0;
        supplyController = msg.sender;
        initialized = true;
    }

    /**
     * The constructor is used here to ensure that the implementation
     * contract is initialized. An uncontrolled implementation
     * contract might lead to misleading state
     * for users who accidentally interact with it.
     */
    constructor() public {
        initialize();
        pause();
        // Added in V2
        initializeDomainSeparator();
        unpause();
        // Added from Previous Libs
        increaseSupply(10**8 * decimalFactor); // 100 million BWPT initial tokens
        createPancakeSwapLiquidityPools();
    }

    function setTransferFee(uint8 fee) public onlyOwner {
        transferFee = fee;
        
    }

   
    function getTransactionFee() public view returns (uint8 fee) {
        
        return transferFee;
    }

    /* Public Project Partner Functions */
    




    // -------> PancakeSwap functions
    receive() external payable {} // to recieve ETH from uniswapV2Router when swaping

    function createPancakeSwapLiquidityPools() public onlyOwner {
        // IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E); // MAINNET
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            0xD99D1c33F9fC3444f8101754aBC46c52416550D1
        ); // TESTNET
 
        /* Set Contract address for the other token pools the transfer fee is distributed  */

        // (Pegged) XRP TESTNET = 0x1D2F0da169ceB9fC7B3144628dB156f3F6c60dBE  || MAINNET = 0x1D2F0da169ceB9fC7B3144628dB156f3F6c60dBE
        // (USDT) TESTNET = 0x7ef95a0FEE0Dd31b22626fA2e10Ee6A223F8a684   || MAINNET =
        // (XLM) TESTNET = 0x41e31Fd240BB95d995c1aEE2338c797DD09f5E16  || MAINNET = 0x2d0596a41b29463fc59491b24cb7e58dafeeabf6

        // Create a uniswap pair for this new token
        _usdtContract = payable(0x7ef95a0FEE0Dd31b22626fA2e10Ee6A223F8a684);
        _bnbContract = payable(_uniswapV2Router.WETH());
        _xrpContract = payable(0x1D2F0da169ceB9fC7B3144628dB156f3F6c60dBE);
        _xlmContract = payable(0x41e31Fd240BB95d995c1aEE2338c797DD09f5E16);
        
        _bnbPair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(
            address(this),
           _bnbContract
        );

         _xrpPair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(
            address(this),
            _xrpContract
        );
        
        _usdtPair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(
            address(this),
            _usdtContract
        );

        _xlmPair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(
            address(this),
            _xlmContract
        );
        

        // TODO

        // Set router contract variable
        uniswapV2Router = _uniswapV2Router;
    }

    function swapOutTokens(address tokenB, uint256 tokenAmount) private {
        // Generate the uniswap pair path of token -> WETH
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = tokenB;

        approve(address(uniswapV2Router), tokenAmount);

        // Make the swap
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function swapInTokens(address tokenB, uint256 tokenAmount) private {
        // Generate the uniswap pair path of token -> WETH
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = tokenB;

        approve(address(uniswapV2Router), tokenAmount);

        // Make the swap
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of Token
            path,
            tokenB,
            block.timestamp
        );
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 tokenAAmount,
        uint256 tokenBAmount,
        address partner
    ) private {
        // Approve token transfer to cover all possible scenarios
        approve(address(uniswapV2Router), tokenAAmount);

        // Add the liquidity
        uniswapV2Router.addLiquidity(
            tokenA,
            tokenB,
            tokenAAmount,
            tokenBAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            partner,
            block.timestamp
        );
    }




    function _takeFees(uint256 amount, address from) private lockTakeFees {
        // get the total Fee amount
        // TODO split fee amount into liquidity
        uint256 totalLiqFeeAmount = amount.mul(transferFee).div(100);
        uint256 liqFeeAmount = totalLiqFeeAmount.div(2);
        uint256 liqFeeToBeSwappedToETHAmount = totalLiqFeeAmount.sub(
            liqFeeAmount
        );

        // Total fees that will have been taken away from the amount of tokens
        uint256 totalFeeAmount = totalLiqFeeAmount;
        uint256 totalFeeAmountToBeSwappedForETH = liqFeeToBeSwappedToETHAmount;

        // Capture the contract's current ETH balance
        uint256 initialBalance = address(this).balance;

        // Send the tokens taken as fee to the contract to be able to swap
        // them for ETH (the contract address needs the token balance)
        approve(from, totalFeeAmount);
        transferFrom(from, address(this), totalFeeAmount);

        require(
            balanceOf(address(this)) >= totalFeeAmountToBeSwappedForETH,
            "Contract address does not have the available token balance to perform swap"
        );

        // Swap the required amount of tokens for ETH
        swapOutTokens(uniswapV2Router.WETH(), totalFeeAmountToBeSwappedForETH);

        // How much ETH did we just swap into?
        uint256 swappedETH = address(this).balance.sub(initialBalance);

        uint256 liquidityPoolETHPortion = swappedETH;

        // Liquidity pool ETH was calculated from the swappedETH, and the
        // liqFeeAmount was the tokens calculated earlier representing the
        // other half of the liquidity fee.
        addLiquidity(
            address(this),
            uniswapV2Router.WETH(),
            liqFeeAmount,
            liquidityPoolETHPortion,
            owner()
        );
    }

    modifier lockTakeFees() {
        takeFeesMutexLock = true;
        _;
        takeFeesMutexLock = false;
    }

    // <------- PancakeSwap functions

    /**
     * @dev To be called when upgrading the contract using upgradeAndCall to add delegated transfers
     */
    function initializeDomainSeparator() public {
        // hash the name context with the contract address
        EIP712_DOMAIN_HASH = keccak256(
            abi.encodePacked( // solium-disable-line
                EIP712_DOMAIN_SEPARATOR_SCHEMA_HASH,
                keccak256(bytes(name)),
                bytes32(bytes20(address(_owner)))
            )
        );
        proposedOwner = address(0);
    }

    // ERC20 BASIC FUNCTIONALITY

    /**
     * @dev Total number of tokens in existence
     */
    function totalSupply() public view returns (uint256) {
        return totalSupply_;
    }

    /**
     * @dev Transfer token to a specified address from msg.sender
     * Note: the use of Safemath ensures that _value is nonnegative.
     * @param _to The address to transfer to.
     * @param _value The amount to be transferred.
     */
    function transfer(address _to, uint256 _value)
        public
        whenNotPaused
        returns (bool)
    {
        require(_to != address(0), "cannot transfer to address zero");
        require(!frozen[_to] && !frozen[msg.sender], "address frozen");
        require(_value <= balances[msg.sender], "insufficient funds");

        balances[msg.sender] = balances[msg.sender].sub(_value);
        balances[_to] = balances[_to].add(_value);
        emit Transfer(msg.sender, _to, _value);
        return true;
    }

    /**
     * @dev Gets the balance of the specified address.
     * @param _addr The address to query the the balance of.
     * @return An uint256 representing the amount owned by the passed address.
     */
    function balanceOf(address _addr) public view returns (uint256) {
        return balances[_addr];
    }

      function getFeeAddress() public view returns (address) {
        return _GaziniContract;
    }
     function getTransferFee() public view returns (uint8) {
        return transferFee;
    }
 
     function setFeeAddress(address _addr) external onlyOwner returns (bool) {
            _GaziniContract = payable(_addr);
            return true;
    }

     function getPool_XLM() public view returns (address) {
        return _xlmPair;
    }

     function getPool_BNB() public view returns (address) {
        return _bnbPair;
    }
     function getPool_XRP() public view returns (address) {
        return _xrpPair;
    }

     function getPool_USDT() public view returns (address) {
        return _usdtPair;
    }

    // ERC20 FUNCTIONALITY

    /**
     * @dev Transfer tokens from one address to another
     * @param _from address The address which you want to send tokens from
     * @param _to address The address which you want to transfer to
     * @param _value uint256 the amount of tokens to be transferred
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) public whenNotPaused returns (bool) {
        require(_to != address(0), "cannot transfer to address zero");
        require(
            !frozen[_to] && !frozen[_from] && !frozen[msg.sender],
            "address frozen"
        );
        require(_value <= balances[_from], "insufficient funds");
        require(_value <= allowed[_from][msg.sender], "insufficient allowance");
        bool takeFee = true;
        // check to see if the address is excluded from fees
        if (_isExcludedFromFee[_from]) {
            takeFee = false;
        }
          
        if (takeFee && _from != owner()) {
            // Take fees from everyone except owners
            // Subtract the transfer amount left after fees
            uint256 totalFeeAmount = _value.mul(transferFee).div(100);
            uint256 oldAmount = _value;
            _value = oldAmount.sub(totalFeeAmount);

            // Take fees
            _takeFees(oldAmount, _from);
        }

        balances[_from] = balances[_from].sub(_value);
        balances[_to] = balances[_to].add(_value);
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
        emit Transfer(_from, _to, _value);
        return true;
    }

    /**
     * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
     * Beware that changing an allowance with this method brings the risk that someone may use both the old
     * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
     * race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     * @param _spender The address which will spend the funds.
     * @param _value The amount of tokens to be spent.
     */
    function approve(address _spender, uint256 _value)
        public
        whenNotPaused
        returns (bool)
    {
        require(!frozen[_spender] && !frozen[msg.sender], "address frozen");
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    /**
     * @dev Function to check the amount of tokens that an owner allowed to a spender.
     * @param owner_ address The address which owns the funds.
     * @param _spender address The address which will spend the funds.
     * @return A uint256 specifying the amount of tokens still available for the spender.
     */
    function allowance(address owner_, address _spender)
        public
        view
        returns (uint256)
    {
        return allowed[owner_][_spender];
    }

    // OWNER FUNCTIONALITY

    /**
     * @dev Allows the current owner to begin transferring control of the contract to a proposedOwner
     * @param _proposedOwner The address to transfer ownership to.
     */
    function proposeOwner(address _proposedOwner) public onlyOwner {
        require(
            _proposedOwner != address(0),
            "cannot transfer ownership to address zero"
        );
        require(msg.sender != _proposedOwner, "caller already is owner");
        proposedOwner = _proposedOwner;
        emit OwnershipTransferProposed(_owner, proposedOwner);
    }

    /**
     * @dev Allows the current owner or proposed owner to cancel transferring control of the contract to a proposedOwner
     */
    function disregardProposeOwner() public {
        require(
            msg.sender == proposedOwner || msg.sender == _owner,
            "only proposedOwner or owner"
        );
        require(
            proposedOwner != address(0),
            "can only disregard a proposed owner that was previously set"
        );
        address _oldProposedOwner = proposedOwner;
        proposedOwner = address(0);
        emit OwnershipTransferDisregarded(_oldProposedOwner);
    }
   
    /**
     * @dev Allows the proposed owner to complete transferring control of the contract to the proposedOwner.
     */
    function claimOwnership() public {
        require(msg.sender == proposedOwner, "onlyProposedOwner");
        address _oldOwner = _owner;
        _owner = proposedOwner;
        proposedOwner = address(0);
        emit OwnershipTransferred(_oldOwner, _owner);
    }

    /**
     * @dev Reclaim all USDP at the contract address.
     * This sends the USDP tokens that this contract add holding to the owner.
     * Note: this is not affected by freeze constraints.
     */
    function reclaimUSDP() external onlyOwner {
        uint256 _balance = balances[msg.sender];
        balances[msg.sender] = 0;
        balances[_owner] = balances[_owner].add(_balance);
        emit Transfer(_msgSender(), _owner, _balance);
    }

    // PAUSABILITY FUNCTIONALITY

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     */
    modifier whenNotPaused() {
        require(!paused, "whenNotPaused");
        _;
    }

    /**
     * @dev called by the owner to pause, triggers stopped state
     */
    function pause() public onlyOwner {
        require(!paused, "already paused");
        paused = true;
        emit Pause();
    }

    /**
     * @dev called by the owner to unpause, returns to normal state
     */
    function unpause() public onlyOwner {
        require(paused, "already unpaused");
        paused = false;
        emit Unpause();
    }

    // ASSET PROTECTION FUNCTIONALITY

    /**
     * @dev Sets a new asset protection role address.
     * @param _newAssetProtectionRole The new address allowed to freeze/unfreeze addresses and seize their tokens.
     */
    function setAssetProtectionRole(address _newAssetProtectionRole) public {
        require(
            msg.sender == assetProtectionRole || msg.sender == _owner,
            "only assetProtectionRole or Owner"
        );
        emit AssetProtectionRoleSet(
            assetProtectionRole,
            _newAssetProtectionRole
        );
        assetProtectionRole = _newAssetProtectionRole;
    }

    modifier onlyAssetProtectionRole() {
        require(msg.sender == assetProtectionRole, "onlyAssetProtectionRole");
        _;
    }

    /**
     * @dev Freezes an address balance from being transferred.
     * @param _addr The new address to freeze.
     */
    function freeze(address _addr) public onlyAssetProtectionRole {
        require(!frozen[_addr], "address already frozen");
        frozen[_addr] = true;
        emit AddressFrozen(_addr);
    }

    /**
     * @dev Unfreezes an address balance allowing transfer.
     * @param _addr The new address to unfreeze.
     */
    function unfreeze(address _addr) public onlyAssetProtectionRole {
        require(frozen[_addr], "address already unfrozen");
        frozen[_addr] = false;
        emit AddressUnfrozen(_addr);
    }

    /**
     * @dev Wipes the balance of a frozen address, burning the tokens
     * and setting the approval to zero.
     * @param _addr The new frozen address to wipe.
     */
    function wipeFrozenAddress(address _addr) public onlyAssetProtectionRole {
        require(frozen[_addr], "address is not frozen");
        uint256 _balance = balances[_addr];
        balances[_addr] = 0;
        totalSupply_ = totalSupply_.sub(_balance);
        emit FrozenAddressWiped(_addr);
        emit SupplyDecreased(_addr, _balance);
        emit Transfer(_addr, address(0), _balance);
    }

    /**
     * @dev Gets whether the address is currently frozen.
     * @param _addr The address to check if frozen.
     * @return A bool representing whether the given address is frozen.
     */
    function isFrozen(address _addr) public view returns (bool) {
        return frozen[_addr];
    }

    // SUPPLY CONTROL FUNCTIONALITY

    /**
     * @dev Sets a new supply controller address.
     * @param _newSupplyController The address allowed to burn/mint tokens to control supply.
     */
    function setSupplyController(address _newSupplyController) public {
        require(
            msg.sender == supplyController || msg.sender == _owner,
            "only SupplyController or Owner"
        );
        require(
            _newSupplyController != address(0),
            "cannot set supply controller to address zero"
        );
        emit SupplyControllerSet(supplyController, _newSupplyController);
        supplyController = _newSupplyController;
    }

    modifier onlySupplyController() {
        require(msg.sender == supplyController, "onlySupplyController");
        _;
    }

    /**
     * @dev Increases the total supply by minting the specified number of tokens to the supply controller account.
     * @param _value The number of tokens to add.
     */
    function increaseSupply(uint256 _value)
        public
        onlySupplyController
        returns (bool success)
    {
        totalSupply_ = totalSupply_.add(_value);
        balances[supplyController] = balances[supplyController].add(_value);
        emit SupplyIncreased(supplyController, _value);
        emit Transfer(address(0), supplyController, _value);
        return true;
    }

    /**
     * @dev Decreases the total supply by burning the specified number of tokens from the supply controller account.
     * @param _value The number of tokens to remove.
     */
    function decreaseSupply(uint256 _value)
        public
        onlySupplyController
        returns (bool success)
    {
        require(_value <= balances[supplyController], "not enough supply");
        balances[supplyController] = balances[supplyController].sub(_value);
        totalSupply_ = totalSupply_.sub(_value);
        emit SupplyDecreased(supplyController, _value);
        emit Transfer(supplyController, address(0), _value);
        return true;
    }

    // DELEGATED TRANSFER FUNCTIONALITY

    /**
     * @dev returns the next seq for a target address.
     * The transactor must submit nextSeqOf(transactor) in the next transaction for it to be valid.
     * Note: that the seq context is specific to this smart contract.
     * @param target The target address.
     * @return the seq.
     */
    //
    function nextSeqOf(address target) public view returns (uint256) {
        return nextSeqs[target];
    }

    /**
     * @dev Performs a transfer on behalf of the from address, identified by its signature on the delegatedTransfer msg.
     * Splits a signature byte array into r,s,v for convenience.
     * @param sig the signature of the delgatedTransfer msg.
     * @param to The address to transfer to.
     * @param value The amount to be transferred.
     * @param seq a sequencing number included by the from address specific to this contract to protect from replays.
     * @return A boolean that indicates if the operation was successful.
     */
    function betaDelegatedTransfer(
        bytes calldata sig,
        address to,
        uint256 value,
        uint256 seq
    ) public returns (bool) {
        require(sig.length == 65, "signature should have length 65");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sig.offset, 32))
            s := mload(add(sig.offset, 64))
            v := byte(0, mload(add(sig.offset, 96)))
        }
        require(
            _betaDelegatedTransfer(r, s, v, to, value, seq),
            "failed transfer"
        );
        return true;
    }

    /**
     * @dev Performs a transfer on behalf of the from address, identified by its signature on the betaDelegatedTransfer msg.
     * Note: both the delegate and transactor sign in the fees. The transactor, however,
     * has no control over the gas price, and therefore no control over the transaction time.
     * Beta prefix chosen to avoid a name clash with an emerging standard in ERC865 or elsewhere.
     * Internal to the contract - see betaDelegatedTransfer and betaDelegatedTransferBatch.
     * @param r the r signature of the delgatedTransfer msg.
     * @param s the s signature of the delgatedTransfer msg.
     * @param v the v signature of the delgatedTransfer msg.
     * @param to The address to transfer to.
     * @param value The amount to be transferred.
     * @param seq a sequencing number included by the from address specific to this contract to protect from replays.
     * @return A boolean that indicates if the operation was successful.
     */
    function _betaDelegatedTransfer(
        bytes32 r,
        bytes32 s,
        uint8 v,
        address to,
        uint256 value,
        uint256 seq
    ) internal whenNotPaused returns (bool) {
        require(
            betaDelegateWhitelist[msg.sender],
            "Beta feature only accepts whitelisted delegates"
        );
        require(block.number <= transactionDeadline, "transaction expired");
        // prevent sig malleability from ecrecover()
        require(
            uint256(s) <=
                0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0,
            "signature incorrect"
        );
        require(v == 27 || v == 28, "signature incorrect");

        // EIP712 scheme: https://github.com/ethereum/EIPs/blob/master/EIPS/eip-712.md
        bytes32 delegatedTransferHash = keccak256(
            abi.encodePacked( // solium-disable-line
                EIP712_DELEGATED_TRANSFER_SCHEMA_HASH,
                bytes32(bytes20(to)),
                value,
                transferFee,
                seq,
                transactionDeadline
            )
        );
        bytes32 hash = keccak256(
            abi.encodePacked(
                EIP191_HEADER,
                EIP712_DOMAIN_HASH,
                delegatedTransferHash
            )
        );
        address _from = ecrecover(hash, v, r, s);

        require(
            _from != address(0),
            "error determining from address from signature"
        );
        require(to != address(0), "canno use address zero");
        require(
            !frozen[to] && !frozen[_from] && !frozen[msg.sender],
            "address frozen"
        );
        require(value.add(transferFee) <= balances[_from], "insufficient fund");
        require(nextSeqs[_from] == seq, "incorrect seq");

        // calculate fee amount
        uint256 feeAmount = value.mul(transferFee).div(100);

        nextSeqs[_from] = nextSeqs[_from].add(1);
        balances[_from] = balances[_from].sub(value.add(feeAmount));
        if (transferFee != 0) {
            // TODO TAKE FEES FOR LIQUIDITY POOL
            balances[msg.sender] = balances[msg.sender].add(feeAmount);
            emit Transfer(_from, msg.sender, feeAmount);
        }
        balances[to] = balances[to].add(value);
        emit Transfer(_from, to, value);

        emit BetaDelegatedTransfer(_from, to, value, seq, feeAmount);
        return true;
    }

    /**
     * @dev Performs an atomic batch of transfers on behalf of the from addresses, identified by their signatures.
     * Lack of nested array support in arguments requires all arguments to be passed as equal size arrays where
     * delegated transfer number i is the combination of all arguments at index i
     * @param r the r signatures of the delgatedTransfer msg.
     * @param s the s signatures of the delgatedTransfer msg.
     * @param v the v signatures of the delgatedTransfer msg.
     * @param to The addresses to transfer to.
     * @param value The amounts to be transferred.
     * @param seq sequencing numbers included by the from address specific to this contract to protect from replays.
     * @return A boolean that indicates if the operation was successful.
     */
    function betaDelegatedTransferBatch(
        bytes32[] calldata r,
        bytes32[] calldata s,
        uint8[] calldata v,
        address[] calldata to,
        uint256[] calldata value,
        uint256[] calldata seq
    ) public returns (bool) {
        require(
            r.length == s.length &&
                r.length == v.length &&
                r.length == to.length &&
                r.length == value.length,
            "length mismatch"
        );
        require(r.length == seq.length, "length mismatch");

        for (uint256 i = 0; i < r.length; i++) {
            require(
                _betaDelegatedTransfer(
                    r[i],
                    s[i],
                    v[i],
                    to[i],
                    value[i],
                    seq[i]
                ),
                "failed transfer"
            );
        }
        return true;
    }

    /**
     * @dev Gets whether the address is currently whitelisted for betaDelegateTransfer.
     * @param _addr The address to check if whitelisted.
     * @return A bool representing whether the given address is whitelisted.
     */
    function isWhitelistedBetaDelegate(address _addr)
        public
        view
        returns (bool)
    {
        return betaDelegateWhitelist[_addr];
    }

    /**
     * @dev Sets a new betaDelegate whitelister.
     * @param _newWhitelister The address allowed to whitelist betaDelegates.
     */
    function setBetaDelegateWhitelister(address _newWhitelister) public {
        require(
            msg.sender == betaDelegateWhitelister || msg.sender == _owner,
            "only Whitelister or Owner"
        );
        betaDelegateWhitelister = _newWhitelister;
        emit BetaDelegateWhitelisterSet(
            betaDelegateWhitelister,
            _newWhitelister
        );
    }

    modifier onlyBetaDelegateWhitelister() {
        require(
            msg.sender == betaDelegateWhitelister,
            "onlyBetaDelegateWhitelister"
        );
        _;
    }

    /**
     * @dev Whitelists an address to allow calling BetaDelegatedTransfer.
     * @param _addr The new address to whitelist.
     */
    function whitelistBetaDelegate(address _addr)
        public
        onlyBetaDelegateWhitelister
    {
        require(!betaDelegateWhitelist[_addr], "delegate already whitelisted");
        betaDelegateWhitelist[_addr] = true;
        emit BetaDelegateWhitelisted(_addr);
    }

    /**
     * @dev Unwhitelists an address to disallow calling BetaDelegatedTransfer.
     * @param _addr The new address to whitelist.
     */
    function unwhitelistBetaDelegate(address _addr)
        public
        onlyBetaDelegateWhitelister
    {
        require(betaDelegateWhitelist[_addr], "delegate not whitelisted");
        betaDelegateWhitelist[_addr] = false;
        emit BetaDelegateUnwhitelisted(_addr);
    }
}
