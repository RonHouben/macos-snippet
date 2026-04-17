import Foundation
import Observation

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case permissions
    case shortcuts
    case theme
    case finish

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome:
            "Welcome"
        case .permissions:
            "Permissions"
        case .shortcuts:
            "Keyboard"
        case .theme:
            "Theme"
        case .finish:
            "Finish"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            "Set up snippingTool for a smooth first capture."
        case .permissions:
            "Grant the access macOS needs for screen capture and global shortcuts."
        case .shortcuts:
            "Choose the keyboard shortcut and capture behavior you want."
        case .theme:
            "Choose how the app should look."
        case .finish:
            "Confirm everything is ready before you start capturing."
        }
    }
}

@Observable
@MainActor
final class OnboardingState {
    var currentStep: OnboardingStep = .welcome

    var canGoBack: Bool {
        currentStep != .welcome
    }

    var isLastStep: Bool {
        currentStep == .finish
    }

    func canAdvance(needsAnyPermission: Bool) -> Bool {
        switch currentStep {
        case .permissions:
            needsAnyPermission == false
        default:
            true
        }
    }

    func goToPreviousStep() {
        guard let previous = OnboardingStep(rawValue: currentStep.rawValue - 1) else {
            return
        }

        currentStep = previous
    }

    func goToNextStep() {
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else {
            return
        }

        currentStep = next
    }
}
