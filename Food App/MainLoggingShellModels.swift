import Foundation

enum SwipeAxis {
    case undecided, horizontal, vertical
}

enum DetailsDrawerMode {
    case full
    case manualAdd
}

enum CameraInputSource {
    case takePicture
    case photo

    var statusMessage: String {
        switch self {
        case .takePicture:
            return "Captured photo ready for parsing."
        case .photo:
            return "Selected photo ready for parsing."
        }
    }
}
