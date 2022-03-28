import pytest
from brownie import config, Wei, Contract

# Snapshots the chain before each test and reverts after test completion.


@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass


# this is the name we want to give our strategy
@pytest.fixture(scope="module")
def strategy_name():
    strategy_name = "boo_Xboo_veLp_Oxdao"
    yield strategy_name


@pytest.fixture(scope="module")
def wftm():
    yield Contract("0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83")


@pytest.fixture(scope="module")
def weth():
    yield Contract("0x74b23882a30290451A17c44f4F05243b6b58C76d")


@pytest.fixture(scope="module")
def oxd():
    yield Contract("0xc5A9848b9d145965d821AaeC8fA32aaEE026492d")


@pytest.fixture(scope="module")
def solid():
    yield Contract("0x888EF71766ca594DED1F0FA3AE64eD2941740A20")


@pytest.fixture(scope="module")
def wbtc():
    yield Contract("0x321162Cd933E2Be498Cd2267a90534A804051b11")


@pytest.fixture(scope="module")
def dai():
    yield Contract("0x8D11eC38a3EB5E956B052f67Da8Bdc9bef8Abf3E")


@pytest.fixture(scope="module")
def usdc():
    yield Contract("0x04068DA6C83AFCFA0e13ba15A6696662335D5B75")


@pytest.fixture(scope="module")
def mim():
    yield Contract("0x82f0B8B456c1A451378467398982d4834b6829c1")


@pytest.fixture(scope="module")
def boo():
    yield Contract("0x841FAD6EAe12c286d1Fd18d1d525DFfA75C7EFFE")


@pytest.fixture(scope="module")
def xboo():
    yield Contract("0xa48d959AE2E88f1dAA7D5F611E01908106dE7598")


@pytest.fixture(scope="module")	
def ox_pool():	
    yield Contract("0x12EE63e73d6BC0327439cdF700ab40849e8e4284")	
@pytest.fixture(scope="module")	
def multi_rewards():	
    yield Contract("0x77831Ced767f0e24Cc69EcFc137ba45305ebC415")


# Define relevant tokens and contracts in this section
@pytest.fixture(scope="module")
def token(boo):
    yield boo


@pytest.fixture(scope="module")
def whale(accounts):
    # Update this with a large holder of your want token (the largest EOA holder of LP)
    whale = accounts.at(
        "0x0D0707963952f2fBA59dD06f2b425ace40b492Fe", force=True)
    yield whale


# this is the amount of funds we have our whale deposit. adjust this as needed based on their wallet balance
@pytest.fixture(scope="module")
def amount(token):  # use today's exchange rates to have similar $$ amounts
    amount = 5000 * (10 ** token.decimals())
    yield amount


# Only worry about changing things above this line, unless you want to make changes to the vault or strategy.
# ----------------------------------------------------------------------- #

# reward_token was set as oxdv1 - maybe because it's not used in the tests because of tradeFactory ???
@pytest.fixture(scope="module")
def reward_token(accounts):
    reward_token = Contract("0xc165d941481e68696f43EE6E99BFB2B23E0E3114")
    yield reward_token


@pytest.fixture(scope="module")
def healthCheck():
    yield Contract("0xf13Cd6887C62B5beC145e30c38c4938c5E627fe0")


@pytest.fixture(scope="module")
def liveBooStrat():
    yield Contract("0xADE3BaC94177295329474aAd6A253Bae979BFA68")


@pytest.fixture(scope="module")
def multicall_swapper():
    yield Contract("0x590B3e12Ded77dE66CBF45050cD07a65d1F51dDD")


@pytest.fixture(scope="module")
def spooky_router():
    yield Contract("0xF491e7B69E4244ad4002BC14e878a34207E38c29")


@pytest.fixture(scope="module")
def solidly_router():
    yield Contract("0xa38cd27185a464914D3046f0AB9d43356B34829D") # was previously wrongly called solidex_router


# zero address


@pytest.fixture(scope="module")
def zero_address():
    zero_address = "0x0000000000000000000000000000000000000000"
    yield zero_address


# Define any accounts in this section
# for live testing, governance is the strategist MS; we will update this before we endorse
# normal gov is ychad, 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52
@pytest.fixture(scope="module")
def gov(accounts):
    yield accounts.at("0xC0E2830724C946a6748dDFE09753613cd38f6767", force=True)


@pytest.fixture(scope="module")
def strategist_ms(accounts):
    # like governance, but better
    yield accounts.at("0x72a34AbafAB09b15E7191822A679f28E067C4a16", force=True)


@pytest.fixture(scope="module")
def keeper(accounts):
    yield accounts.at("0xBedf3Cf16ba1FcE6c3B751903Cf77E51d51E05b8", force=True)


@pytest.fixture(scope="module")
def rewards(accounts):
    yield accounts.at("0xBedf3Cf16ba1FcE6c3B751903Cf77E51d51E05b8", force=True)


@pytest.fixture(scope="module")
def guardian(accounts):
    yield accounts[2]


@pytest.fixture
def trade_factory():
    # yield Contract("0xBf26Ff7C7367ee7075443c4F95dEeeE77432614d")
    yield Contract("0xD3f89C21719Ec5961a3E6B0f9bBf9F9b4180E9e9")


@pytest.fixture(scope="module")
def management(accounts):
    yield accounts[3]


@pytest.fixture
def ymechs_safe(accounts):
    yield accounts.at("0x9f2A061d6fEF20ad3A656e23fd9C814b75fd5803", force=True)


@pytest.fixture(scope="module")
def strategist(accounts):
    yield accounts.at("0xBedf3Cf16ba1FcE6c3B751903Cf77E51d51E05b8", force=True)


# # list any existing strategies here
# @pytest.fixture(scope="module")
# def LiveStrategy_1():
#     yield Contract("0xC1810aa7F733269C39D640f240555d0A4ebF4264")


# use this if you need to deploy the vault
@pytest.fixture(scope="function")
def vault(pm, gov, rewards, guardian, management, token, chain):
    Vault = pm(config["dependencies"][0]).Vault
    vault = guardian.deploy(Vault)
    vault.initialize(token, gov, rewards, "", "", guardian)
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    vault.setManagement(management, {"from": gov})
    chain.sleep(1)
    yield vault


# use this if your vault is already deployed
# @pytest.fixture(scope="function")
# def vault(pm, gov, rewards, guardian, management, token, chain):
#     vault = Contract("0x497590d2d57f05cf8B42A36062fA53eBAe283498")
#     yield vault


# replace the first value with the name of your strategy
@pytest.fixture(scope="function")
def strategy(
    Strategy,
    strategist,
    keeper,
    vault,
    gov,
    strategy_name,
    trade_factory,
    ymechs_safe
):
    # make sure to include all constructor parameters needed here
    strategy = strategist.deploy(
        Strategy,
        vault,
        strategy_name

    )
    trade_factory.grantRole(
        trade_factory.STRATEGY(), strategy, {
            "from": ymechs_safe, "gas_price": "0 gwei"}
    )
    strategy.setKeeper(keeper, {"from": gov})
    # set our management fee to zero so it doesn't mess with our profit checking
    vault.setManagementFee(0, {"from": gov})
    # add our new strategy
    vault.addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    # strategy.setHealthCheck(healthCheck, {"from": gov}) - set in strat
    yield strategy


# use this if your strategy is already deployed
# @pytest.fixture(scope="function")
# def strategy():
#     # parameters for this are: strategy, vault, max deposit, minTimePerInvest, slippage protection (10000 = 100% slippage allowed),
#     strategy = Contract("0xC1810aa7F733269C39D640f240555d0A4ebF4264")
#     yield strategy
