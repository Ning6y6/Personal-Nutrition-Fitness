/// User-reported provenance, never a claim that medical advice was independently verified.
public enum GoalSource: String, Codable, CaseIterable, Equatable, Sendable {
    case selfSelected
    case userProvidedReference
}
