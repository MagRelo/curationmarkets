pragma solidity ^0.4.10;

import "./ERC20Token.sol";

/*
DO NOT USE. This is a still a WIP.

Code is MIT licensed.
*/

/*
Continuous Token is about the minting/withdrawing of the curation market.
It allows tokens to be minted, the ETH kept in a pool, and then withdrawn from supply.
This can be re-used without the bonding functionality.
*/
contract ContinuousToken is ERC20Token {

    uint public constant MAX_UINT = (2**256) - 1;

    uint256 baseCost = 100000000000000; //100000000000000 wei 0.0001 ether

    uint256 public buyPrice = 0;
    uint256 public sellPrice = 0;

    uint256 public totalEverMinted;
    uint256 public totalEverWithdrawn;
    uint256 public poolBalance;

    uint8 decimals;
    string symbol;
    string name;

    function ContinuousToken(uint8 _decimals, string _symbol, string _name) {
        decimals = _decimals;
        symbol = _symbol;
        name = _name;
        updateCostOfToken(0); //first pass
    }

    // via: http://ethereum.stackexchange.com/questions/10425/is-there-any-efficient-way-to-compute-the-exponentiation-of-a-fraction-and-an-in/10432#10432
    // Computes `k * (1+1/q) ^ N`, with precision `p`. The higher
    // the precision, the higher the gas cost. It should be
    // something around the log of `n`. When `p == n`, the
    // precision is absolute (sans possible integer overflows).
    // Much smaller values are sufficient to get a great approximation.
    function fracExp(uint k, uint q, uint n, uint p) internal returns (uint) {
      uint s = 0;
      uint N = 1;
      uint B = 1;
      for (uint i = 0; i < p; ++i){
        s += k * N / B / (q**i);
        N  = N * (n-i);
        B  = B * (i+1);
      }
      return s;
    }

    //mint
    function mint(uint256 _amountToMint) payable returns (bool) {
        //balance of msg.sender increases if paid right amount according to protocol

        if(_amountToMint > 0 && (MAX_UINT - _amountToMint) >= totalSupply && msg.value > 0) {

            uint256 totalMinted = 0;
            uint256 totalCost = 0;
            //for loop to determine cost at each point.
            for(uint i = 0; i < _amountToMint; i+=1) {
                if(totalCost + buyPrice <= msg.value) {
                    totalCost += buyPrice;
                    totalMinted += 1;
                    updateCostOfToken((totalSupply+i));
                } else {
                    break;
                }
            }

            if(totalCost < msg.value) { //some funds left, not enough for one token. Send back funds
                msg.sender.transfer(msg.value - totalCost);
            }

            totalEverMinted += totalMinted;
            totalSupply += totalMinted;
            balances[msg.sender] += totalMinted;
            poolBalance += totalCost;

            LogMint(totalMinted, totalCost);

            return true;
        } else {
            throw;
        }
    }

    function withdraw(uint256 _amountToWithdraw) returns (bool) {
        if(_amountToWithdraw > 0 && balances[msg.sender] >= _amountToWithdraw) {
            //determine how much you can leave with.
            uint256 reward = _amountToWithdraw * sellPrice; //rounding?
            msg.sender.transfer(reward);
            balances[msg.sender] -= _amountToWithdraw;
            totalSupply -= _amountToWithdraw;
            updateCostOfToken(totalSupply);
            LogWithdraw(_amountToWithdraw, reward);
            return true;
        } else {
            throw;
        }
    }

    function updateCostOfToken(uint256 _supply) internal {

        buyPrice = calulateBuyPrice(_supply);
        sellPrice = calulateSellPrice();

        LogCostOfTokenUpdate(buyPrice);
    }


    /*
    These functions can be designed to influence network dynamics.
    Currently they are both based on totalSupply but these functions
    can be arbitrarily complex and dynamic.

    Some interesting parameters:

    - Attributes of the token/trade
    -- # tokens in trasaction
    -- age of token (vesting)
    -- age of token (demmurage/appreciation)

    - Activity of the sender wallet:
    -- recent trade activity (e.g., discourage dumping)

    - Network activity:
    -- trading volume - 90 day, 30 day, 3 day, 6 hour, etc.
    -- # of unique wallets/changes in uniques wallets
    -- # of trading connections, richness

    - Outside factors:
    -- imported config files
    -- oracles

    These parameters could be combined in interesting ways to create different
    incentives at different points in the group's lifecycle. For example, when
    the totalSupply is low we could encourage unique connections. As the totalSupply grows
    we could transition the incentives toward holding tokens, or whatever.

    */

    function calulateBuyPrice(uint256 _supply) internal {
        //from protocol design:
        //costOfCoupon = (BaseCost + BaseCost*(1.000001618^AvailableSupply)+BaseCost*AvailableSupply/1000)
        //totalSupply == AvailableSupply
        return baseCost+fracExp(baseCost, 618046, _supply, 2)+baseCost*_supply/1000;
    }


    function calulateSellPrice() internal {
        return poolBalance/totalSupply;
    }


    event LogMint(uint256 amountMinted, uint256 totalCost);
    event LogWithdraw(uint256 amountWithdrawn, uint256 reward);
    event LogCostOfTokenUpdate(uint256 newCost);
}

/*
Implements a continuous token that can be bonded to curators and subtopic for curation.
*/
contract CurationToken is ContinuousToken {

    //token holder -> curator -> sub-topic -> amount
    mapping (address => mapping (address => mapping(string => uint256))) public bonds;
    mapping (address => mapping(string => uint256)) public totalBondsPerCuratorPerSubtopic;

    uint256 public totalBonded = 0;

    //main topic. eg #truffle. Hardcoded.
    //sub topics examples = #truffle.features or #truffle.pullrequests
    string topic;

    function CurationToken(uint8 _decimals, string _symbol, string _name, string _topic) ContinuousToken(_decimals, _symbol, _name) {
        topic = _topic;
    }

    function bond(address _curator, string _subtopic, uint256 _amount) returns (bool) {
        if(balances[msg.sender] >= _amount) {
            bonds[msg.sender][_curator][_subtopic] += _amount;
            balances[msg.sender] -= _amount;
            totalBonded += _amount;
            totalBondsPerCuratorPerSubtopic[_curator][_subtopic] += _amount;
            LogBond(msg.sender, _curator, _subtopic, _amount);
            return true;
        } else {
            return false;
        }
    }

    function withdrawBond(address _curator, string _subtopic, uint256 _amount) returns (bool) {
        if(bonds[msg.sender][_curator][_subtopic] >= _amount) {
            bonds[msg.sender][_curator][_subtopic] -= _amount;
            balances[msg.sender] += _amount;
            totalBonded -= _amount;
            totalBondsPerCuratorPerSubtopic[_curator][_subtopic] -= _amount;
            LogWithdrawBond(msg.sender, _curator, _subtopic, _amount);
            return true;
        } else {
            return false;
        }
    }


    event LogBond(address indexed holder, address curator, string subtopic, uint256 amount);
    event LogWithdrawBond(address indexed holder, address curator, string subtopic, uint256 amount);

}

/*
Back information with full backing in that subtopic
Currently just uses event logs.
Have to build a local DB to filter these events.
No internal storage atm.
*/
contract Curator {

    function back(address _token, string _subtopic, string _info) {
        CurationToken token = CurationToken(_token);
        LogBacking(msg.sender, _info, token.totalBondsPerCuratorPerSubtopic(msg.sender, _subtopic), token.totalBonded());
    }

    function revoke(address _token, string _subtopic, string _info) {
        CurationToken token  = CurationToken(_token);
        LogRevoke(msg.sender, _info, token.totalBondsPerCuratorPerSubtopic(msg.sender, _subtopic), token.totalBonded());
    }

    event LogBacking(address curator, string info, uint256 bondedAmount, uint256 totalBonded);
    event LogRevoke(address curator, string info, uint256 bondedAmount, uint256 totalBonded);
}
