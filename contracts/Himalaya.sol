// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

// Safe Math library
library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        c = a + b;
        require(c >= a, "addition overflow");
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require(b <= a, "subtraction overflow");
        c = a - b;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        c = a * b;
        require(a == 0 || c / a == b, "multiplication overflow");
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require(b > 0, "division by zero");
        c = a / b;
    }
}

// ----------------------------------------------------------------------------
/// @notice ERC Token Standard #20 Interface
/// @dev ERC Token Standard #20 Interface
// ----------------------------------------------------------------------------
interface ERC20Interface {
    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256 balance);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256 remaining);

    function transfer(address to, uint256 tokens)
        external
        returns (bool success);

    function approve(address spender, uint256 tokens)
        external
        returns (bool success);

    function transferFrom(
        address from,
        address to,
        uint256 tokens
    ) external returns (bool success);

    event Transfer(address indexed from, address indexed to, uint256 tokens);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 tokens
    );
}

// ----------------------------------------------------------------------------
/// @notice Contract function to receive approval and execute function in one call
/// @dev Contract function to receive approval and execute function in one call
// ----------------------------------------------------------------------------
interface ApproveAndCallFallBack {
    function receiveApproval(
        address from,
        uint256 tokens,
        address token,
        bytes calldata data
    ) external;
}

// ----------------------------------------------------------------------------
/// @notice Owned Contract
/// @dev Owned Contract
// ----------------------------------------------------------------------------
contract Owned {
    address public owner;
    address public newOwner;

    event OwnershipTransferred(address indexed _from, address indexed _to);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "unauthorised call");
        _;
    }

    function transferOwnership(address _newOwner) public onlyOwner {
        newOwner = _newOwner;
    }

    function acceptOwnership() public {
        require(msg.sender == newOwner, "unauthorised call");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
        newOwner = address(0);
    }
}

// ----------------------------------------------------------------------------
/// @notice DAI Medianiser Interface
/// @dev DAI Medianiser Interface
// ----------------------------------------------------------------------------
interface MedianiserInterface {
    function peek() external view returns (bytes32, bool);
}

// ----------------------------------------------------------------------------
/// @title Himalaya Stable Coin
/// @author Hersh Pathak
/// @notice Defines an ERC20 token which manages the Himalaya coin and its ETH pool
/// @dev Defines an ERC20 token which manages the Himalaya coin and its ETH pool
// ----------------------------------------------------------------------------
contract Himalaya is ERC20Interface, Owned {
    using SafeMath for uint256;
    uint256 private constant MAX_UINT256 = 2**256 - 1;

    string public symbol;
    string public name;
    uint8 public decimals;
    uint256 _totalSupply;
    uint256 lastPriceAdjustment;
    uint256 timeBetweenPriceAdjustments;

    mapping(address => uint256) balances;
    mapping(address => mapping(address => uint256)) allowed;

    MedianiserInterface medianiser;

    event Burn(address indexed owner, uint256 tokens);
    event gotHCXN(
        address indexed caller,
        uint256 amountGivenEther,
        uint256 amountReceivedHCXN
    );
    event gotEther(
        address indexed caller,
        uint256 amountGivenHCXN,
        uint256 amountReceivedEther
    );
    event Inflate(uint256 previousPoolSize, uint256 amountMinted);
    event Deflate(uint256 previousPoolSize, uint256 amountBurned);
    event NoAdjustment();
    event FailedAdjustment();

    // ----------------------------------------------------------------------------
    /// @notice This creates the HCXN and creates HCXN tokens for the pool
    /// @dev Contract constructor which accepts no parameters
    /// @param medianiserAddress address of the medianiser contract
    // ----------------------------------------------------------------------------
    constructor(
        address medianiserAddress,
        uint256 setTimeBetweenPriceAdjustments
    ) payable {
        symbol = "HCXN";
        name = "HimalayaStableCoin";
        decimals = 18;
        lastPriceAdjustment = block.timestamp;
        timeBetweenPriceAdjustments = setTimeBetweenPriceAdjustments;

        medianiser = MedianiserInterface(medianiserAddress);

        uint256 feedPrice;
        bool priceIsValid;
        (feedPrice, priceIsValid) = getOraclePriceETH_USD();
        require(priceIsValid, "oracle failure");

        _totalSupply = feedPrice.mul(address(this).balance).div(
            10**uint256(decimals)
        );
        balances[address(this)] = _totalSupply;
        emit Transfer(address(0), address(this), _totalSupply);
    }

    // ------------------------------------------------------------------------
    /// @notice Get the current total supply of HCXN tokens
    /// @dev Get the current total supply of HCXN tokens
    /// @return total supply of HCXN tokens
    // ------------------------------------------------------------------------
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    // ------------------------------------------------------------------------
    /// @notice Get the HCXN balance of a given address
    /// @dev Get the HCXN balance of a given address
    /// @param owner The address to find the HCXN balance of
    /// @return balance HCXN balance of owner
    // ------------------------------------------------------------------------
    function balanceOf(address owner)
        public
        view
        override
        returns (uint256 balance)
    {
        return balances[owner];
    }

    // ------------------------------------------------------------------------
    /// @notice Transfer HCXN tokens from a user to another user. Doesn't allow transfers to 0x0 address (use burn())
    /// @dev Transfer HCXN tokens from a user to another user. Doesn't allow transfers to 0x0 address (use burn())
    /// @param to Address to send tokens to
    /// @param tokens Quantity of tokens to send
    /// @return success true if transfer is successful
    // ----------------f--------------------------------------------------------
    function transfer(address to, uint256 tokens)
        public
        override
        canTriggerPriceAdjustment
        returns (bool success)
    {
        require(to != address(0), "can't send to 0 address, use burn");
        if (to == address(this)) getEther(tokens);
        else {
            balances[msg.sender] = balances[msg.sender].sub(tokens);
            balances[to] = balances[to].add(tokens);
            emit Transfer(msg.sender, to, tokens);
        }
        return true;
    }

    // ------------------------------------------------------------------------
    /// @notice Burn HCXN Tokens
    /// @dev Burn HCXN Tokens
    /// @param tokens Quantity of tokens to burn
    /// @return success true if burn is successful
    // ------------------------------------------------------------------------
    function burn(uint256 tokens)
        public
        canTriggerPriceAdjustment
        returns (bool success)
    {
        _totalSupply = _totalSupply.sub(tokens);
        balances[msg.sender] = balances[msg.sender].sub(tokens);
        emit Burn(msg.sender, tokens);
        emit Transfer(msg.sender, address(0), tokens);
        return true;
    }

    // ------------------------------------------------------------------------
    /// @notice Token owner can approve for `spender` to `transferFrom(...)` `tokens` from the token owner's account
    /// @dev Token owner can approve for `spender` to `transferFrom(...)` `tokens` from the token owner's account
    /// @param spender Address to authorise to spend tokens on your behalf
    /// @param tokens Quantity of tokens to authorise for spending
    /// @return success true if approval is successful
    // ------------------------------------------------------------------------
    function approve(address spender, uint256 tokens)
        public
        override
        canTriggerPriceAdjustment
        returns (bool success)
    {
        allowed[msg.sender][spender] = tokens;
        emit Approval(msg.sender, spender, tokens);
        return true;
    }

    // ------------------------------------------------------------------------
    /// @notice Transfer `tokens` from the `from` account to the `to` account. Caller must be approved to spend these funds. Can't be to the HCXN contract (for conversion).
    /// @dev Transfer `tokens` from the `from` account to the `to` account. Caller must be approved to spend these funds. Can't be to the HCXN contract (for conversion).
    /// @param from Address to transfer tokens from
    /// @param to Address tokens will be transferred to. Can't be the HCXN contract's address
    /// @param tokens Quantity of tokens to transfer (must be approvedd by `to` address)
    /// @return success true if approval is successful
    // ------------------------------------------------------------------------
    function transferFrom(
        address from,
        address to,
        uint256 tokens
    ) public override canTriggerPriceAdjustment returns (bool success) {
        require(to != address(0), "can't send to 0 address, use burn");
        require(to != address(this), "can't transfer to self");
        balances[from] = balances[from].sub(tokens);
        if (allowed[from][msg.sender] < MAX_UINT256) {
            allowed[from][msg.sender] = allowed[from][msg.sender].sub(tokens);
        }
        balances[to] = balances[to].add(tokens);
        emit Transfer(from, to, tokens);
        return true;
    }

    // ------------------------------------------------------------------------
    /// @notice Get the amount of tokens approved by an address `owner` for use by `spender`
    /// @dev Get the amount of tokens approved by an address `owner` for use by `spender`
    /// @param owner The address owner whose tokens we want to verify approval for
    /// @param spender The address of the potentially approved spender
    /// @return allowanceHCXN the amount of HCXN `spender` is approved to transfer on behalf of `owner`
    // ------------------------------------------------------------------------
    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256 allowanceHCXN)
    {
        return allowed[owner][spender];
    }

    // ------------------------------------------------------------------------
    /// @notice Token owner can approve for `spender` to transferFrom(...) `tokens` from the token owner's account. The `spender` contract function `receiveApproval(...)` is then executed
    /// @dev Token owner can approve for `spender` to transferFrom(...) `tokens` from the token owner's account. The `spender` contract function `receiveApproval(...)` is then executed
    /// @param spender The contract address to be approved
    /// @param tokens The number of tokens the caller is approving for `spender` to use
    /// @param data The function call data provided to `spender.receiveApproval()`
    /// @return success true if call is successful
    // ------------------------------------------------------------------------
    function approveAndCall(
        address spender,
        uint256 tokens,
        bytes memory data
    ) public canTriggerPriceAdjustment returns (bool success) {
        allowed[msg.sender][spender] = tokens;
        emit Approval(msg.sender, spender, tokens);
        ApproveAndCallFallBack(spender).receiveApproval(
            msg.sender,
            tokens,
            address(this),
            data
        );
        return true;
    }

    // ------------------------------------------------------------------------
    /// @notice Ether can be sent directly to the contract in exchange for HCXN (if sufficient gas is provided)
    /// @dev Ether can be sent directly to the contract in exchange for HCXN (if sufficient gas is provided)
    // ------------------------------------------------------------------------
    receive() external payable {
        getHCXN();
    }

    // Runs a price feed adjustment if more than timeBetweenPriceAdjustments has passed
    modifier canTriggerPriceAdjustment() {
        _;
        if (
            block.timestamp >= lastPriceAdjustment + timeBetweenPriceAdjustments
        ) priceFeedAdjustment();
    }

    // ------------------------------------------------------------------------
    /// @notice Gets the seconds until the next price adjustment
    /// @dev Gets the seconds until the next price adjustment
    /// @return nextPriceAdjustmentTime seconds to next price adjustment, or 0 if this will take place after the next conversion transaction
    // ------------------------------------------------------------------------
    function getNextPriceAdjustmentTime()
        public
        view
        returns (uint256 nextPriceAdjustmentTime)
    {
        if (
            block.timestamp >= lastPriceAdjustment + timeBetweenPriceAdjustments
        ) return 0;
        else
            return
                lastPriceAdjustment +
                timeBetweenPriceAdjustments -
                block.timestamp;
    }

    // ------------------------------------------------------------------------
    /// @notice Provides the caller with HCXN in return for Ether
    /// @dev Provides the caller with HCXN in return for Ether
    /// @return success true if the transaction is successful
    /// @return amountReceivedHCXN the amount of HCXN received by the caller
    // ------------------------------------------------------------------------
    function getHCXN()
        public
        payable
        canTriggerPriceAdjustment
        returns (bool success, uint256 amountReceivedHCXN)
    {
        amountReceivedHCXN = balances[address(this)]
            .mul(msg.value.mul(10**8).div(address(this).balance))
            .div(10**8);
        balances[address(this)] = balances[address(this)].sub(
            amountReceivedHCXN
        );
        balances[msg.sender] = balances[msg.sender].add(amountReceivedHCXN);
        emit gotHCXN(msg.sender, msg.value, amountReceivedHCXN);
        emit Transfer(address(this), msg.sender, amountReceivedHCXN);
        return (true, amountReceivedHCXN);
    }

    // ------------------------------------------------------------------------
    /// @notice Provides the caller with Ether in return for HCXN
    /// @dev Provides the caller with Ether in return for HCXN
    /// @param amountGivenHCXN the quantity of HCXN you want to exchange for Ether
    /// @return success true if the transaction was successful
    /// @return amountReceivedEther the amount of Ether received by the caller
    // ------------------------------------------------------------------------
    function getEther(uint256 amountGivenHCXN)
        public
        canTriggerPriceAdjustment
        returns (bool success, uint256 amountReceivedEther)
    {
        amountReceivedEther = address(this)
            .balance
            .mul(
                amountGivenHCXN.mul(10**8).div(
                    balances[address(this)].add(amountGivenHCXN)
                )
            )
            .div(10**8);
        balances[address(this)] = balances[address(this)].add(amountGivenHCXN);
        balances[msg.sender] = balances[msg.sender].sub(amountGivenHCXN);
        emit gotEther(msg.sender, amountGivenHCXN, amountReceivedEther);
        emit Transfer(msg.sender, address(this), amountGivenHCXN);
        payable(msg.sender).transfer(amountReceivedEther);
        return (true, amountReceivedEther);
    }

    // ------------------------------------------------------------------------
    /// @notice Get the quantity of Ether and HCXN in the pools
    /// @dev Get the quantity of Ether and HCXN in the pools
    /// @return balanceETH the amount of Ether in the pool
    /// @return balanceHCXN the amount of HCXN in the pool
    // ------------------------------------------------------------------------
    function getPoolBalances()
        public
        view
        returns (uint256 balanceETH, uint256 balanceHCXN)
    {
        return (address(this).balance, balanceOf(address(this)));
    }

    // ------------------------------------------------------------------------
    /// @notice Increase the size of the ETH pool WITHOUT GAINING ANYTHING
    /// @dev Increase the size of the ETH pool WITHOUT GAINING ANYTHING
    /// @return success true if the transaction is successful
    // ------------------------------------------------------------------------
    function inflateEtherPool() public payable returns (bool success) {
        return true;
    }

    // ------------------------------------------------------------------------
    /// @notice Gets the current ETH_USD exchange rate, according to the MakerDAO Oracle
    /// @dev Gets the current ETH_USD exchange rate, according to the MakerDAO Oracle
    /// @return priceETH_USD the current ETH_USD exchange rate
    /// @return priceIsValid true if oracle says it has a value
    // ------------------------------------------------------------------------
    function getOraclePriceETH_USD()
        public
        view
        returns (uint256 priceETH_USD, bool priceIsValid)
    {
        bytes32 price;
        (price, priceIsValid) = medianiser.peek();
        return (uint256(price), priceIsValid);
    }

    // ------------------------------------------------------------------------
    /// @notice (private) Performs a pool size adjustment (+/- 10% of the difference) if > 1% deviation
    /// @dev (private) Performs a pool size adjustment (+/- 10% of the difference) if > 1% deviation
    /// @return newPoolHCXN The new size of the HCXN pool
    // ------------------------------------------------------------------------
    function priceFeedAdjustment() private returns (uint256 newPoolHCXN) {
        uint256 feedPrice;
        bool priceIsValid;
        (feedPrice, priceIsValid) = getOraclePriceETH_USD();

        if (!priceIsValid) {
            newPoolHCXN = balances[address(this)];
            lastPriceAdjustment = block.timestamp;
            emit FailedAdjustment();
            return (newPoolHCXN);
        }

        feedPrice = feedPrice.mul(address(this).balance).div(
            10**uint256(decimals)
        );
        if (feedPrice > (balances[address(this)] / 100) * 101) {
            uint256 posDelta = feedPrice.sub(balances[address(this)]).div(10);
            newPoolHCXN = balances[address(this)].add(posDelta);
            emit Inflate(balances[address(this)], posDelta);
            emit Transfer(address(0), address(this), posDelta);
            balances[address(this)] = newPoolHCXN;
            _totalSupply = _totalSupply.add(posDelta);
        } else if (feedPrice < (balances[address(this)] / 100) * 99) {
            uint256 negDelta = balances[address(this)].sub(feedPrice).div(10);
            newPoolHCXN = balances[address(this)].sub(negDelta);
            emit Deflate(balances[address(this)], negDelta);
            emit Transfer(address(this), address(0), negDelta);
            balances[address(this)] = newPoolHCXN;
            _totalSupply = _totalSupply.sub(negDelta);
        } else {
            newPoolHCXN = balances[address(this)];
            emit NoAdjustment();
        }
        lastPriceAdjustment = block.timestamp;
    }

    // ------------------------------------------------------------------------
    /// @notice Allows the contract owner to withdraw wasted tokens
    /// @dev Allows the contract owner to withdraw wasted tokens
    /// @param tokenAddress the contract address of the token to be transferred
    /// @param tokens the quantity of tokens to be transferred
    /// @return success true if the transaction is successful
    // ------------------------------------------------------------------------
    function transferAnyERC20Token(address tokenAddress, uint256 tokens)
        public
        onlyOwner
        returns (bool success)
    {
        require(tokenAddress != address(this), "can't withdraw HCXN");
        return ERC20Interface(tokenAddress).transfer(owner, tokens);
    }
}
