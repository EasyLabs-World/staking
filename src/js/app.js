/* global $, web3, Web3, UI */

const App = {

  rpcurl: 'http://127.0.0.1:7545',
  web3Provider: null,
  contracts: {},
  activeInstance: null,
  account: null,

  init: function () {
    console.log('App.init')
    App.initWeb3()
  },

  initWeb3: function () {
    // define App.web3Provider
    if (typeof web3 !== 'undefined') {
      if (web3.currentProvider.isMetaMask) {
        console.log('Metamask detected')
      } else {
        console.log('Metamask not detected, found other web3')
      }
      App.web3Provider = web3.currentProvider
    } else {
      // If no injected web3 instance is detected, fall back to Ganache
      // TODO: verify correct server for testing
      console.log('create new web3')
      // use 127.0.0.1 is better than localhost (no network access required)
      // https://truffleframework.com/docs/advanced/truffle-with-metamask#using-metamask-with-truffle-develop
      App.web3Provider = new Web3.providers.HttpProvider(App.rpcurl)
      // global assignment on purpose
    }
    // define global web3 with provider
    web3 = new Web3(App.web3Provider) // eslint-disable-line no-global-assign
    App.getActiveAccount()
  },

  initContract: function () {
    $.getJSON('./js/StakePool.json')
      .done(function (data) {
        console.log('Contract Data: ', data)
        // instantiate new contract
        App.contracts.StakePool = new web3.eth.Contract(
          data.abi,
          data.networks['5777'].address
        )
        UI.enableElemById('#b_trx')
        App.getBalance()
      })
      .fail(function (jqxhr, textStatus, error) {
        let err = textStatus + ', ' + error
        console.log(jqxhr)
        console.log('Failed to find Smart Contract: ' + err)
        UI.disableElemById('#b_trx')
      })
  },

  getActiveAccount: function () {
    // getAccounts returns a promise -- must use .then to receive result
    // use multiple .then to execute actions in sequence
    // .catch to catch errors
    web3.eth.getAccounts().then((result) => {
      // TODO: if metamask is not logged in, promise returns empty array
      // 'this' is App object same as function getActiveAccount
      console.log('Promise value: ', result)
      return App.updateAccount(result[0])
    }).then((account) => {
      // account returned as string
      console.log(account)
      // make sure that contract is init only once
      if (Object.keys(App.contracts).length === 0) {
        App.initContract()
      } else {
        App.updateAccount(account)
      }
    }).catch((reason) => {
      // Log the rejection reason
      console.log('Handle rejected promise (' + reason + ') here.')
    })
  },

  /* @param acct string
   *
   */
  updateAccount: function (acct) {
    App.account = acct
    $('#t_account').text(acct)
    return App.account
  },

  sendEther: function (value, target) {
    web3.eth.sendTransaction({
      from: App.account,
      to: target,
      value: web3.utils.toWei(value, 'ether')
    }).then((result) => {
      console.log('Promise value: ', result)
    }).catch((reason) => {
      // Log the rejection reason
      console.log('Handle rejected promise (' + reason + ') here.')
    })
  },

  sendTransaction: function (value) {
    // TODO: value must be <= 18 decimal places -- otherwise fails
    App.contracts.StakePool.methods.deposit()
      .send({from: App.account, value: web3.utils.toWei(value, 'ether')})
      .on('transactionHash', (hash) => {
        console.log('trx_Hash: ', hash)
      })
      .on('receipt', (receipt) => {
        console.log('Receipt: ', receipt)
      })
      .on('confirmation', (confirmationNumber, receipt) => {
        // TODO: Why output 24 confirmations ??
        console.log('Conf: ', confirmationNumber)
        console.log('receipt: ', receipt)
        App.getBalance()
      })
      .on('error', console.error)
  },

  getBalance: function () {
    App.contracts.StakePool.methods.getBalance().call({
      from: App.account
    }).then((value) => {
      // @value param string
      console.log('Update Balance: ', value)
      // value is in wei, display in ether
      $('#s_value').text(web3.utils.fromWei(value, 'ether'))
    }).catch((reason) => {
      console.error('Rejected balance request: ', reason)
    })
  }

}

/* setup related event listeners */
/* b_ => buttons */
$('#b_refresh').on('click', () => {
  App.getActiveAccount()
})

$('#b_trx').on('click', () => {
  // App.sendEther('1', '0x5755B9Bf6bf9d4bE8Bb36eCC8D212a3C329899ab')
  console.log('click#b_trx')
  console.log($('#i_value').val())
  // default account is null
  // console.log(web3.eth.defaultAccount)
  App.sendTransaction($('#i_value').val())
})

$('#b_balance').on('click', () => {
  console.log('click#b_balance')
  App.getBalance()
})
