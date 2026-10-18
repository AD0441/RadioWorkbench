import RadioCore

enum WorkbenchDestination: Hashable {
    case broadcasts
    case propagation
    case consultations
    case library
    case receptionMap
    case rigctl
    case workshop
    case satDump
    case externalEvents
    case decoder(RadioMode)
}
