// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;
// Gary's Branch - BOO/xBOO - 0xDAO
// These are the core Yearn libraries
import {BaseStrategy, StrategyParams} from "@yearnvaults/contracts/BaseStrategy.sol";
import {SafeERC20, SafeMath, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";

interface IOxPool {
    function stakingAddress() external view returns (address);

    function solidPoolAddress() external view returns (address);

    // function solidPoolInfo() external view returns (ISolidlyLens.Pool memory);

    function depositLpAndStake(uint256) external;

    function depositLp(uint256) external;

    function withdrawLp(uint256) external;

    function syncBribeTokens() external;

    function notifyBribeOrFees() external;

    function initialize(
        address,
        address,
        address,
        string memory,
        string memory,
        address,
        address
    ) external;

    function gaugeAddress() external view returns (address);

    function balanceOf(address) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);
}

interface IMultiRewards {
    struct Reward {
        address rewardsDistributor;
        uint256 rewardsDuration;
        uint256 periodFinish;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
    }

    function stake(uint256) external;

    function withdraw(uint256) external;

    function getReward() external;

    function stakingToken() external view returns (address);

    function balanceOf(address) external view returns (uint256);

    function earned(address, address) external view returns (uint256);

    function initialize(address, address) external;

    function rewardRate(address) external view returns (uint256);

    function getRewardForDuration(address) external view returns (uint256);

    function rewardPerToken(address) external view returns (uint256);

    function rewardData(address) external view returns (Reward memory);

    function rewardTokensLength() external view returns (uint256);

    function rewardTokens(uint256) external view returns (address);

    function totalSupply() external view returns (uint256);

    function addReward(
        address _rewardsToken,
        address _rewardsDistributor,
        uint256 _rewardsDuration
    ) external;

    function notifyRewardAmount(address, uint256) external;

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external;

    function setRewardsDuration(address _rewardsToken, uint256 _rewardsDuration)
        external;

    function exit() external;
}

interface ISolidlyRouter {
    function addLiquidity(
        address,
        address,
        bool,
        uint256,
        uint256,
        uint256,
        uint256,
        address,
        uint256
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function quoteRemoveLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity
    ) external view returns (uint256 amountA, uint256 amountB);
}

// boo:xboo ratios, enter = "Locks Boo and mints xBoo", leave = "Unlocks the staked + gained Boo, and burns xBoo"
interface IXboo is IERC20 {
    function xBOOForBOO(uint256) external view returns (uint256);

    function BOOForxBOO(uint256) external view returns (uint256);

    function enter(uint256) external;

    function leave(uint256) external;
}

interface ITradeFactory {
    function enable(address, address) external;
}

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    // swap stuff
    address internal constant solidlyRouter =
        0xa38cd27185a464914D3046f0AB9d43356B34829D;
    bool public tradesEnabled;
    bool public realiseLosses;
    bool public depositerAvoid;
    address public tradeFactory =
        address(0xD3f89C21719Ec5961a3E6B0f9bBf9F9b4180E9e9);
    
    address public solidPoolAddress = 
        address(0x5804F6C40f44cF7593F73cf3aa16F7037213A623);
    address public oxPoolAddress = 
        address(0x12EE63e73d6BC0327439cdF700ab40849e8e4284);
    address public stakingAddress = 
        address(0x77831Ced767f0e24Cc69EcFc137ba45305ebC415);

    IERC20 internal constant solidLp =
        IERC20(0x5804F6C40f44cF7593F73cf3aa16F7037213A623); // Solidly BOO/xBOO
    IERC20 internal constant oxLp =
        IERC20(0x12EE63e73d6BC0327439cdF700ab40849e8e4284); // 0xDAO BOO/xBOO

    IERC20 internal constant boo =
        IERC20(0x841FAD6EAe12c286d1Fd18d1d525DFfA75C7EFFE);
    IXboo internal constant xboo =
        IXboo(0xa48d959AE2E88f1dAA7D5F611E01908106dE7598);

    IERC20 internal constant oxd =
        IERC20(0xc5A9848b9d145965d821AaeC8fA32aaEE026492d);
    IERC20 internal constant solid =
        IERC20(0x888EF71766ca594DED1F0FA3AE64eD2941740A20);

    uint256 public lpSlippage = 9950; //0.5% slippage allowance

    uint256 immutable DENOMINATOR = 10_000;

    string internal stratName; // we use this for our strategy's name on cloning
    address public lpToken =
        address(0x5804F6C40f44cF7593F73cf3aa16F7037213A623);
    
    IOxPool public oxPool =
        IOxPool(0x12EE63e73d6BC0327439cdF700ab40849e8e4284);
    IMultiRewards public multiRewards =
        IMultiRewards(0x77831Ced767f0e24Cc69EcFc137ba45305ebC415);

    bool internal forceHarvestTriggerOnce; // only set this to true externally when we want to trigger our keepers to harvest for us
    uint256 public minHarvestCredit; // if we hit this amount of credit, harvest the strategy

    /* ========== CONSTRUCTOR ========== */

    constructor(address _vault, string memory _name)
        public
        BaseStrategy(_vault)
    {
        require(vault.token() == address(boo));
        _initializeStrat(_name);
    }

    /* ========== CLONING ========== */

    event Cloned(address indexed clone);

    // this is called by our original strategy, as well as any clones
    function _initializeStrat(string memory _name) internal {
        // initialize variables
        maxReportDelay = 43200; // 1/2 day in seconds, if we hit this then harvestTrigger = True
        healthCheck = address(0xf13Cd6887C62B5beC145e30c38c4938c5E627fe0); // Fantom common health check

        // set our strategy's name
        stratName = _name;

        // turn off our credit harvest trigger to start with
        minHarvestCredit = type(uint256).max;

        // add approvals on all tokens
        IERC20(lpToken).approve(address(solidlyRouter), type(uint256).max);
        xboo.approve(address(solidlyRouter), type(uint256).max);
        boo.approve(address(xboo), type(uint256).max);
        boo.approve(address(solidlyRouter), type(uint256).max);
        // NEW ONES
        IERC20(solidPoolAddress).approve(oxPoolAddress, type(uint256).max);
        IERC20(oxPoolAddress).approve(stakingAddress, type(uint256).max);
    }

    /* ========== VIEWS ========== */

    function name() external view override returns (string memory) {
        return stratName;
    }

    // balance of boo in strat - should be zero most of the time
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfXbooInWant(uint256 xbooAmount)
        public
        view
        returns (uint256)
    {
        return xboo.xBOOForBOO(xbooAmount);
    }

    // view our balance of unstaked oxLP tokens - should be zero most of the time
    function balanceOfOxPool() public view returns (uint256) {
        return oxPool.balanceOf(address(this));
    }

    // view our balance of staked oxLP tokens
    function balanceOfMultiRewards() public view returns (uint256) {
        return multiRewards.balanceOf(address(this));
    }

    // view our balance of unstaked and staked oxLP tokens
    function balanceOfLPStaked() public view returns (uint256) {
        return balanceOfOxPool().add(balanceOfMultiRewards());
    }

    function balanceOfConstituents(uint256 liquidity)
        public
        view
        returns (uint256 amountBoo, uint256 amountXBoo)
    {
        (amountBoo, amountXBoo) = ISolidlyRouter(solidlyRouter)
            .quoteRemoveLiquidity(
                address(boo),
                address(xboo),
                false, // volatile pool
                liquidity
            );
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        uint256 lpTokens = balanceOfLPStaked().add(
            IERC20(lpToken).balanceOf(address(this))
        );

        (uint256 amountBoo, uint256 amountXBoo) = balanceOfConstituents(
            lpTokens
        );

        uint256 balanceOfxBooinBoo = balanceOfXbooInWant(
            amountXBoo.add(xboo.balanceOf(address(this)))
        );

        // look at our staked tokens and any free tokens sitting in the strategy
        return balanceOfxBooinBoo.add(balanceOfWant()).add(amountBoo);
    }

    function _setUpTradeFactory() internal {
        //approve and set up trade factory
        address _tradeFactory = tradeFactory;

        ITradeFactory tf = ITradeFactory(_tradeFactory);
        oxd.safeApprove(_tradeFactory, type(uint256).max);
        tf.enable(address(oxd), address(want));

        solid.safeApprove(_tradeFactory, type(uint256).max);
        tf.enable(address(solid), address(want));
        tradesEnabled = true;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        if (tradesEnabled == false && tradeFactory != address(0)) {
            _setUpTradeFactory();
        }
        // claim our rewards
        multiRewards.getReward();

        uint256 assets = estimatedTotalAssets();
        uint256 wantBal = balanceOfWant();

        uint256 debt = vault.strategies(address(this)).totalDebt;
        uint256 amountToFree;

        if (assets >= debt) {
            _debtPayment = _debtOutstanding;
            _profit = assets.sub(debt);

            amountToFree = _profit.add(_debtPayment);
        } else {
            //loss should never happen. so leave blank. small potential for IP i suppose. lets not record if so and handle manually
            //dont withdraw either incase we realise losses
            //withdraw with loss
            if (realiseLosses) {
                _loss = debt.sub(assets);
                if (_debtOutstanding > _loss) {
                    _debtPayment = _debtOutstanding.sub(_loss);
                } else {
                    _debtPayment = 0;
                }

                amountToFree = _debtPayment;
            }
        }

        //amountToFree > 0 checking (included in the if statement)
        if (wantBal < amountToFree) {
            liquidatePosition(amountToFree);

            uint256 newLoose = want.balanceOf(address(this));

            //if we dont have enough money adjust _debtOutstanding and only change profit if needed
            if (newLoose < amountToFree) {
                if (_profit > newLoose) {
                    _profit = newLoose;
                    _debtPayment = 0;
                } else {
                    _debtPayment = Math.min(newLoose.sub(_profit), _debtPayment);
                }
            }
        }

        // we're done harvesting, so reset our trigger if we used it
        forceHarvestTriggerOnce = false;
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }
        // send all of our want tokens to be deposited
        uint256 toInvest = balanceOfWant();
        // stake only if we have something to stake
        // dont bother for less than 0.1 boo
        if (toInvest > 1e17) {
            uint256 booB = boo.balanceOf(lpToken);
            uint256 xbooB = xboo.balanceOf(lpToken);

            //ratio we need of boo to xboo to lp
            uint256 ratio_lp = booB.mul(1e18).div(xbooB);

            //ratio boo to xboo in xBoo
            uint256 ratio_xboo = xboo.xBOOForBOO(1e18);

            //allow 0.5% slippage by default
            if (ratio_lp < ratio_xboo.mul(lpSlippage).div(DENOMINATOR)) {
                //dont do anything because we would be lping into the lp at a bad price
                return;
            }

            if (ratio_xboo < ratio_lp.mul(lpSlippage).div(DENOMINATOR)) {
                //dont do anything because we would be lping into the lp at a bad price
                return;
            }
            //amount to swap is:
            // B0 * Rxboo / (Rlp + Rxboo)
            uint256 numerator = toInvest.mul(ratio_xboo);
            uint256 denom = ratio_xboo.add(ratio_lp);

            uint256 newInvest = (numerator.div(denom)).sub(1e6); // remove a bit incase of rounding error

            // deposit our boo into xboo
            xboo.enter(newInvest);

            // deposit into lp
            ISolidlyRouter(solidlyRouter).addLiquidity(
                address(boo),
                address(xboo),
                false, // volatile pool
                boo.balanceOf(address(this)),
                xboo.balanceOf(address(this)),
                0,
                0,
                address(this),
                2**256 - 1
            );
        }
        uint256 lpBalance = IERC20(lpToken).balanceOf(address(this));

        if (lpBalance > 0) {
            // Transfer Solidly LP to ox pool to receive Ox pool LP receipt token
            oxPool.depositLp(lpBalance);
            // Stake oxLP in multirewards
            multiRewards.stake(oxLp.balanceOf(address(this)));
        }
    }

    //returns lp tokens needed to get that amount of boo
    function booToLpTokens(uint256 amountOfBooWeWant) public returns (uint256) {
        //amount of boo and xboo for 1 lp token
        (uint256 amountBooPerLp, uint256 amountXBoo) = balanceOfConstituents(
            1e18
        );

        //1 lp token is this amount of boo
        amountBooPerLp = amountBooPerLp.add(xboo.xBOOForBOO(amountXBoo));

        uint256 lpTokensWeNeed = amountOfBooWeWant.mul(1e18).div(
            amountBooPerLp
        );

        return lpTokensWeNeed;
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        //if we have loose xboo. liquidated it
        uint256 xbooBal = xboo.balanceOf(address(this));
        if (xbooBal > 1e7) {
            xboo.leave(xbooBal);
        }

        uint256 balanceOfBoo = want.balanceOf(address(this));

        // if we need more boo than is already loose in the contract
        if (balanceOfBoo < _amountNeeded) {
            // boo needed beyond any boo that is already loose in the contract
            uint256 amountToFree = _amountNeeded.sub(balanceOfBoo);

            // converts this amount into lpTokens
            uint256 lpTokensNeeded = booToLpTokens(amountToFree);

            uint256 balanceOfLpTokens = IERC20(lpToken).balanceOf(
                address(this)
            );

            if (balanceOfLpTokens < lpTokensNeeded) {
                uint256 toWithdrawfromOxdao = lpTokensNeeded.sub(
                    balanceOfLpTokens
                );

                // balance of oxlp staked in multiRewards
                uint256 staked = balanceOfLPStaked();

                if (staked > 0) {
                    // Withdraw oxLP from multiRewards
                    multiRewards.withdraw(Math.min(toWithdrawfromOxdao, staked));
                    // balance of oxlp in oxPool
                    uint256 oxLpBalance = oxPool.balanceOf(address(this));
                    // Redeem/burn oxPool LP for Solidly LP
                    oxPool.withdrawLp(Math.min(toWithdrawfromOxdao, oxLpBalance));
                }

                balanceOfLpTokens = IERC20(lpToken).balanceOf(address(this));
            }

            uint256 amountBoo;
            uint256 amountxBoo;
            if (balanceOfLpTokens > 0) {
                (amountBoo, amountxBoo) = ISolidlyRouter(solidlyRouter)
                    .removeLiquidity(
                        address(boo),
                        address(xboo),
                        false,
                        Math.min(lpTokensNeeded, balanceOfLpTokens),
                        0,
                        0,
                        address(this),
                        type(uint256).max
                    );
            }

            xbooBal = xboo.balanceOf(address(this));
            if (xbooBal > 1e7) {
                xboo.leave(xbooBal);
            }

            _liquidatedAmount = Math.min(
                want.balanceOf(address(this)),
                _amountNeeded
            );

            if (_liquidatedAmount < _amountNeeded) {
                _loss = _amountNeeded.sub(_liquidatedAmount);
            }
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        // balance of oxlp staked in multiRewards
        uint256 staked = balanceOfLPStaked();

        if (staked > 0) {
            // Withdraw oxLP from multiRewards
            multiRewards.withdraw(staked);
            // balance of oxlp in oxPool
            uint256 oxLpBalance = oxPool.balanceOf(address(this));
            // Redeem/burn oxPool LP for Solidly LP
            oxPool.withdrawLp(oxLpBalance);
            

            ISolidlyRouter(solidlyRouter).removeLiquidity(
                address(boo),
                address(xboo),
                false,
                IERC20(lpToken).balanceOf(address(this)),
                0,
                0,
                address(this),
                type(uint256).max
            );

            xboo.leave(xboo.balanceOf(address(this)));
        }

        uint256 xbooBal = xboo.balanceOf(address(this));
        if (xbooBal > 0) {
            xboo.leave(xbooBal);
        }

        return balanceOfWant();
    }

    function prepareMigration(address _newStrategy) internal override {
        if (!depositerAvoid) {
            // balance of oxlp staked in multiRewards
            uint256 staked = balanceOfLPStaked();

            if (staked > 0) {
                // Withdraw oxLP from multiRewards
                multiRewards.withdraw(staked);
                // balance of oxlp in oxPool
                uint256 oxLpBalance = oxPool.balanceOf(address(this));
                // Redeem/burn oxPool LP for Solidly LP
                oxPool.withdrawLp(oxLpBalance);
            }
        }

        uint256 lpBalance = IERC20(lpToken).balanceOf(address(this));

        if (lpBalance > 0) {
            IERC20(lpToken).safeTransfer(_newStrategy, lpBalance);
        }

        uint256 xbooBalance = xboo.balanceOf(address(this));

        if (xbooBalance > 0) {
            // send our total balance of xboo to the new strategy
            xboo.transfer(_newStrategy, xbooBalance);
        }
    }

    function manualWithdraw(uint256 amount)
        external
        onlyEmergencyAuthorized
    {
        // Withdraw oxLP from multiRewards
        multiRewards.withdraw(amount);
        // balance of oxlp in oxPool
        uint256 oxLpBalance = oxPool.balanceOf(address(this));
        // Redeem/burn oxPool LP for Solidly LP
        oxPool.withdrawLp(Math.min(amount, oxLpBalance));
    }

    function manualWithdrawPartOne(uint256 amount)
        external
        onlyEmergencyAuthorized
    {
        // Withdraw oxLP from multiRewards
        multiRewards.withdraw(amount);
    }

    function manualWithdrawPartTwo(uint256 amount)
        external
        onlyEmergencyAuthorized
    {
        // Redeem/burn oxPool LP for Solidly LP
        oxPool.withdrawLp(amount);
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {}

    // our main trigger is regarding our DCA since there is low liquidity for our emissionToken
    function harvestTrigger(uint256 callCostinEth)
        public
        view
        override
        returns (bool)
    {
        StrategyParams memory params = vault.strategies(address(this));

        // harvest no matter what once we reach our maxDelay
        if (block.timestamp.sub(params.lastReport) > maxReportDelay) {
            return true;
        }

        // trigger if we want to manually harvest
        if (forceHarvestTriggerOnce) {
            return true;
        }

        // trigger if we have enough credit
        if (vault.creditAvailable() >= minHarvestCredit) {
            return true;
        }

        // otherwise, we don't harvest
        return false;
    }

    function ethToWant(uint256 _amtInWei)
        public
        view
        override
        returns (uint256)
    {}

    function updateTradeFactory(address _newTradeFactory)
        external
        onlyGovernance
    {
        if (tradeFactory != address(0)) {
            _removeTradeFactoryPermissions();
        }

        tradeFactory = _newTradeFactory;
        _setUpTradeFactory();
    }

    function removeTradeFactoryPermissions() external onlyEmergencyAuthorized {
        _removeTradeFactoryPermissions();
    }

    function _removeTradeFactoryPermissions() internal {
        address _tradeFactory = tradeFactory;
        oxd.safeApprove(_tradeFactory, 0);

        solid.safeApprove(_tradeFactory, 0);

        tradeFactory = address(0);
        tradesEnabled = false;
    }

    /* ========== SETTERS ========== */

    ///@notice This allows us to manually harvest with our keeper as needed
    function setForceHarvestTriggerOnce(bool _forceHarvestTriggerOnce)
        external
        onlyEmergencyAuthorized
    {
        forceHarvestTriggerOnce = _forceHarvestTriggerOnce;
    }

    ///@notice When our strategy has this much credit, harvestTrigger will be true.
    function setMinHarvestCredit(uint256 _minHarvestCredit)
        external
        onlyEmergencyAuthorized
    {
        minHarvestCredit = _minHarvestCredit;
    }

    function setRealiseLosses(bool _realiseLoosses) external onlyVaultManagers {
        realiseLosses = _realiseLoosses;
    }

    function setLpSlippage(uint256 _slippage) external onlyEmergencyAuthorized {
        _setLpSlippage(_slippage, false);
    }

    //only vault managers can set high slippage
    function setLpSlippage(uint256 _slippage, bool _force)
        external
        onlyVaultManagers
    {
        _setLpSlippage(_slippage, _force);
    }

    function _setLpSlippage(uint256 _slippage, bool _force) internal {
        require(_slippage <= DENOMINATOR, "higher than max");
        if (!_force) {
            require(_slippage >= 9990, "higher than 1pc slippage set");
        }
        lpSlippage = _slippage;
    }

    function setDepositerAvoid(bool _avoid) external onlyGovernance {
        depositerAvoid = _avoid;
    }
}
