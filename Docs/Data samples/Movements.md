# Data sample for movements

## Bark Lightning Send -> Send -> Successful

{
  "completed_at" : "2026-02-03T19:50:06.132657+01:00",
  "created_at" : "2026-02-03T19:49:56.651992+01:00",
  "effective_balance_sats" : -1000,
  "exited_vtxo_ids" : [

  ],
  "id" : 5,
  "input_vtxo_ids" : [
    "b33f7ba9e1a7c4f1c629b845c81c611b35a461765fdc8582d14de89c94fe639c:0"
  ],
  "intended_balance_sats" : -1000,
  "metadata_json" : "{\"payment_hash\":\"7cec194d8a916e7dd916047e079159b9b65ff5c47e8556b79d232dbb08563211\",\"htlc_vtxos\":[\"d21103e4456edfc2b28b496d224cc395e612d49ebcd13d21d54ff144c7624d41:0\"]}",
  "offchain_fee_sats" : 0,
  "output_vtxo_ids" : [
    "4fedf7f4a54401c8d80a195178065e272ec65f45134e145e4fe11a85da3206bc:0"
  ],
  "received_on_addresses" : [

  ],
  "sent_to_addresses" : [
    "{\"type\":\"invoice\",\"value\":\"lntbs10u1p5cys6dsp5av4gnjpjelahjjg7f9ggyl4splvvzv89fla608tfm5wjl4dwu9fspp50nkpjnv2j9h8mkgkq3lq0y2ehxm9lawy06z4dduayvkmkzzkxggsdq5g9exkgznw3hhyefqyvmqxqzjccqp2rzjq2v454h7kjlfx9c6kcfeprd4d7lsn4cmhsngyuvmx9pr6lmepgu0cpzs55qqqegqqqqqqqqpqqqqqzsqqc9qxpqysgq3hra4xya9s63ngskkhl3xjz9rfz00x72lxkfngshtthmdjqyaapku3e0sr4cxaqe6wyty8kw2nxf4xms205jq3cmndtmdrlq8x2jfesp5h4tj4\"}"
  ],

  "status" : "successful",
  "subsystem_kind" : "send",
  "subsystem_name" : "bark.lightning_send",
  "updated_at" : "2026-02-03T19:49:56.693137+01:00"
}

## Bark Lightning Send -> Receive -> Successful

Bark.Movement(
    id: 16,
    status: "successful",
    subsystemName: "bark.lightning_receive",
    subsystemKind: "receive",
    metadataJson: "{\"payment_hash\":\"7bed06bd8bc8ce56e9a3bd95b9d220cc851d1057e6dd70e3377b6499ffec35ea\",\"htlc_vtxos\":[\"5416fcca47658dcc4f1ff0c38fc8b5fa7f7e3bf9eec378c16df6d592899b40a4:0\"]}",
    intendedBalanceSats: 1000,
    effectiveBalanceSats: 1000,
    offchainFeeSats: 0,
    sentToAddresses: [],
    receivedOnAddresses: ["{\"type\":\"invoice\",\"value\":\"lntbs10u1p5c3cu3sp58cg7vjlltnzc3drjnqhje8ulplwjzst7p2ykp6rgwgq6r9lmv47spp500ksd0vter89d6drhk2mn53qejz36yzhumwhpceh0djfnllvxh4qdqqxqy9gcqcqzpc9qyysgqsdeahlw95rfestjf5wzrvgcw92372zv2qpx7ts0j4zpq4lx6jykq9kr7fvl9psdk782xu6ln60y3ckplwu4dh3qdpzqfgn62sxddhpsq7v89ya\"}"],
    inputVtxoIds: [],
    outputVtxoIds: ["f1683db41567cd476d1430e35f64bd0103acc7ea8cd735710567e1ef998c645b:0"],
    exitedVtxoIds: [],
    createdAt: "2026-02-08T20:28:06.010520+01:00",
    updatedAt: "2026-02-08T20:28:06.172889+01:00",
    completedAt: Optional("2026-02-08T20:28:06.178459+01:00")
)

## Bark Exit -> Start -> Successful

{
    "completed_at" : "2026-02-04T14:18:20.089430+01:00",
    "created_at" : "2026-02-04T14:18:20.078094+01:00",
    "effective_balance_sats" : -2000,
    "exited_vtxo_ids" : [

    ],
    "id" : 23,
    "input_vtxo_ids" : [
        "a48bfc101c36ce7619650e2837cb3b96653a8b78e8e4255d04b8529ed11e6159:0"
    ],
    "intended_balance_sats" : -2000,
    "metadata_json" : "{}",
    "offchain_fee_sats" : 0,
    "output_vtxo_ids" : [

    ],
    "received_on_addresses" : [

    ],
    "sent_to_addresses" : [
        "{\"type\":\"bitcoin\",\"value\":\"tb1pnxuegncypkcwjc206vgzmsa9kgptk0a0yfcwu5zef435x0m3a00sy3w0dg\"}"
    ],
    "status" : "successful",
    "subsystem_kind" : "start",
    "subsystem_name" : "bark.exit",
    "updated_at" : "2026-02-04T14:18:20.089430+01:00"
}

## Bark Arkoor -> Receive -> Successful

Bark.Movement(
    id: 1,
    status: "successful",
    subsystemName: "bark.arkoor",
    subsystemKind: "receive",
    metadataJson: "{}",
    intendedBalanceSats: 789,
    effectiveBalanceSats: 789,
    offchainFeeSats: 0,
    sentToAddresses: [],
    receivedOnAddresses: [],
    inputVtxoIds: [],
    outputVtxoIds: [
        "41fc921d2befcc9b90a84415b8e17eca681d9a81e20791ae58b80d4bb698f29f:0"
    ],
    exitedVtxoIds: [],
    createdAt: "2026-02-02T11:55:35.747481+01:00",
    updatedAt: "2026-02-02T11:55:35.756372+01:00",
    completedAt: Optional("2026-02-02T11:55:35.756372+01:00")
)

## Bark Arkoor -> Send -> Successful

{
    "completed_at" : "2026-02-02T14:31:59.913135+01:00",
    "created_at" : "2026-02-02T14:31:59.869654+01:00",
    "effective_balance_sats" : -400,
    "exited_vtxo_ids" : [

    ],
    "id" : 4,
    "input_vtxo_ids" : [
        "30a7528729260ec96ea41259270682ce75fb0bc68b0acaa8ad423168f221776e:0"
    ],
    "intended_balance_sats" : -400,
    "metadata_json" : "{}",
    "offchain_fee_sats" : 0,
    "output_vtxo_ids" : [
        "fed31dabee411a7c37d1840203fd18bbad6ef3561c356dc5571581cbb3a332aa:0"
    ],
    "received_on_addresses" : [

    ],
    "sent_to_addresses" : [
        "{\"type\":\"ark\",\"value\":\"tark1pem36wcfzqqppsq0q4jle47tnwwht7jhpqu37jhsj989rm2pmf9m3jh83dgwdu6ezqypcd25mwnf0q2w23cz5q4m8wpnd5lpvssgrj2sxuz0yzy4y7srs7ugvzps8l\"}"
    ],
    "status" : "successful",
    "subsystem_kind" : "send",
    "subsystem_name" : "bark.arkoor",
    "updated_at" : "2026-02-02T14:31:59.911363+01:00"
}

## Bark Board -> Board -> Pending

Bark.Movement(
    id: 1,
    status: "pending",
    subsystemName: "bark.board",
    subsystemKind: "board",
    metadataJson: "{\"onchain_fee_sat\":143,\"chain_anchor\":\"751d1b62fc511762945590188e492683ee0d77a76d0227023e31c123ba37c988:0\"}",
    intendedBalanceSats: 20000,
    effectiveBalanceSats: 20000,
    offchainFeeSats: 0,
    sentToAddresses: [],
    receivedOnAddresses: [],
    inputVtxoIds: [],
    outputVtxoIds: ["a6493bfbbf934f45524593cad6ce4e0ffba1a0438566563475a8d56283bde0a6:0"],
    exitedVtxoIds: [],
    createdAt: "2026-02-01T22:24:07.519426+01:00",
    updatedAt: "2026-02-01T22:24:07.531334+01:00",
    completedAt: nil
)

## Bark Round -> Refresh -> Failed

{
    "completed_at" : "2026-02-03T12:25:08.274499+01:00",
    "created_at" : "2026-02-03T09:26:41.312006+01:00",
    "effective_balance_sats" : 0,
    "exited_vtxo_ids" : [

    ],
    "id" : 7,
    "input_vtxo_ids" : [
        "cc11fb785d2d8e9ccdcd8332dae5159d70b4a09758e61d09ca99906f6b0f1e36:0"
    ],
    "intended_balance_sats" : 0,
    "metadata_json" : "{}",
    "offchain_fee_sats" : 0,
    "output_vtxo_ids" : [

    ],
    "received_on_addresses" : [

    ],
    "sent_to_addresses" : [

    ],
    "status" : "failed",
    "subsystem_kind" : "refresh",
    "subsystem_name" : "bark.round",
    "updated_at" : "2026-02-03T09:26:41.320866+01:00"
}

## Bark Round -> Refresh -> Successful

{
    "completed_at" : "2026-02-03T12:37:43.449783+01:00",
    "created_at" : "2026-02-03T12:25:08.350184+01:00",
    "effective_balance_sats" : 0,
    "exited_vtxo_ids" : [

    ],
    "id" : 8,
    "input_vtxo_ids" : [
        "cc11fb785d2d8e9ccdcd8332dae5159d70b4a09758e61d09ca99906f6b0f1e36:0"
    ],
    "intended_balance_sats" : 0,
    "metadata_json" : "{\"funding_txid\":\"d9b15726640d16354ae3cc6048406ed55ff4506973a4cd640d7ea670e8d9c4b9\"}",
    "offchain_fee_sats" : 0,
    "output_vtxo_ids" : [
        "6ed6afa1e2f7ef4ee4c68434a7d3390bffa655f3f91e469072851409eb7ea429:0"
    ],
    "received_on_addresses" : [

    ],
    "sent_to_addresses" : [

    ],
    "status" : "successful",
    "subsystem_kind" : "refresh",
    "subsystem_name" : "bark.round",
    "updated_at" : "2026-02-03T12:37:43.446424+01:00"
}

## Bark Offboard -> Send Onchain -> Successful

{
    "completed_at" : "2026-02-02T12:39:43.113602+01:00",
    "created_at" : "2026-02-02T12:39:43.000323+01:00",
    "effective_balance_sats" : -5536,
    "exited_vtxo_ids" : [

    ],
    "id" : 3,
    "input_vtxo_ids" : [
        "41fc921d2befcc9b90a84415b8e17eca681d9a81e20791ae58b80d4bb698f29f:0",
        "49d61713eb209e4c09595852e5fa4b6f7a103c2a8ad21cf582274838e6a5fb62:0"
    ],
    "intended_balance_sats" : -5000,
    "metadata_json" : "{\"offboard_txid\":\"ab8f2a315d91c32880d89741811b15bd6061baf78f916fe32a865d403267ee88\",\"offboard_tx\":\"02000000000101758f58a8ffd52f957c4b2727da04f113b0c230d4d99ed7c9077e093aeed328c10000000000fdffffff038813000000000000225120845e71ea0cb8f2addddd3f3e7412fb8504e1ec97462ce4ca82051b13d3c7ad869402000000000000225120e1664fe7f35e5367c43717fd1c2c16a509e526f6b119556959a674b7616a3735fa01a07200000000225120d303ea1147410480fdeae04af1f2e9c70528dadaa78a37ccc538481df1a471b80140037f6013eab16623141bdb98c17ad9cefda1d76a228a6221ddcab4b05202a700c1ff26696d90ab185540bb88b7017d71b60c0c3db35e88429371b98c068b900afa6b0400\"}",
    "offchain_fee_sats" : 536,
    "output_vtxo_ids" : [
        "30a7528729260ec96ea41259270682ce75fb0bc68b0acaa8ad423168f221776e:0"
    ],
    "received_on_addresses" : [

    ],
    "sent_to_addresses" : [
        "{\"type\":\"bitcoin\",\"value\":\"tb1ps308r6svhre2mhwa8ul8gyhms5zwrmyhgckwfj5zq5d385784krq225nn5\"}"
    ],

    "status" : "successful",
    "subsystem_kind" : "send_onchain",
    "subsystem_name" : "bark.offboard",
    "updated_at" : "2026-02-02T12:39:43.104609+01:00"
}
