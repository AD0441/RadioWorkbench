import RadioCore

enum WorkbenchDestination: Hashable {
    case broadcasts
    case propagation
    case consultations
    case decoder(RadioMode)
}
