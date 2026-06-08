import NexusCore

/// `NexusCore.Label` collides with `SwiftUI.Label` in every view file that
/// imports both, and the module name `NexusCore` is shadowed by the
/// `public enum NexusCore` declared in that module — so `NexusCore.Label` cannot
/// be written as a qualifier. This file does NOT import SwiftUI, so `Label` here
/// resolves unambiguously to the model; the alias lets view files name the entity
/// without the collision.
typealias TaskLabel = Label
