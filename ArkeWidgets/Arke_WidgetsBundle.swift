//
//  Arke_WidgetsBundle.swift
//  ArkeWidgets
//
//  Created by Christoph on 5/12/26.
//

import WidgetKit
import SwiftUI

@main
struct Arke_WidgetsBundle: WidgetBundle {
    var body: some Widget {
        Arke_Widgets()
        Arke_WidgetsControl()
        ExitProgressLiveActivity()
    }
}
