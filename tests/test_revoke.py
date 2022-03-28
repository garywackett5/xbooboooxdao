import brownie
from brownie import Contract
from brownie import config
import math


def test_revoke_strategy_from_vault(
    gov,
    token,
    vault,
    whale,
    chain,
    strategy,
    amount,
    xboo,
):

    ## deposit to the vault after approving
    startingWhale = token.balanceOf(whale)
    token.approve(vault, 2 ** 256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    chain.sleep(1)
    strategy.setDoHealthCheck(False, {"from": gov})
    strategy.harvest({"from": gov})

    # wait a day
    chain.sleep(86400)
    chain.mine(1)

    vaultAssets_starting = vault.totalAssets()
    vault_holdings_starting = token.balanceOf(vault)
    strategy_starting = strategy.estimatedTotalAssets()
    vault.revokeStrategy(strategy.address, {"from": gov})
    strategy.setRealiseLosses(True, {"from": gov})

    chain.sleep(1)
    strategy.setDoHealthCheck(False, {"from": gov})
    strategy.harvest({"from": gov})
    chain.sleep(1)
    vaultAssets_after_revoke = vault.totalAssets()

    # confirm we made money, or at least that we have about the same
    assert vaultAssets_after_revoke >= vaultAssets_starting or math.isclose(
        vaultAssets_after_revoke, vaultAssets_starting, abs_tol=5
    )
    # ignore dust
    assert strategy.estimatedTotalAssets() <= 100
    assert token.balanceOf(vault) >= vault_holdings_starting + strategy_starting

    # simulate a day of waiting for share price to bump back up
    chain.sleep(86400)
    chain.mine(1)

    # withdraw and confirm we made money
    vault.withdraw({"from": whale})
    assert token.balanceOf(whale) >= startingWhale*0.999
