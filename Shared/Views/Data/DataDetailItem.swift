//
//  DataDetailItem.swift
//  Arké
//
//  Created by Christoph on 12/17/25.
//

import ArkeUI

// Enum to represent the selected item in the data view
enum DataDetailItem: Hashable {
    case vtxo(VTXOModel)
    case utxo(UTXOModel)
}
