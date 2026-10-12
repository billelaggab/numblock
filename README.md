# NumBlock 2048 🚀

A polished, commercial-grade implementation of the classic 2048 puzzle game built with **Flutter**, featuring a modern dark-neon **Merge Infinity** visual identity. Optimized for production, with high-performance gesture handling and full Google AdMob integration, ready for Google Play.

## ✨ Features

- **Modern Dark-Neon UI:** A custom "Merge Infinity" visual identity with glowing neon gradient tiles, a radial-gradient background, and the **Rubik** font family for a premium feel.
- **Single-Step Undo:** Revert the board and score to the exact state before your last move — even after a Game Over.
- **Optimized Performance:** Custom-built game board using `Stack` and `Positioned` widgets to ensure smooth animations and zero gesture conflicts.
- **Responsive Gestures:** Advanced velocity-based swipe detection (Up, Down, Left, Right).
- **Monetization Ready:** Pre-integrated with **Google Mobile Ads (AdMob)**:
  - Persistent **Banner Ads** at the bottom (adaptive placeholder container).
  - **Interstitial Ads** triggered on Game Over, with automatic retry loading.
- **Persistence:** High-score tracking using `shared_preferences`.
- **Game Logic:**
  - Smooth tile pop and scale animations.
  - Dedicated "Win" and "Game Over" states with modern glass-style dialogs.
  - "Keep Playing" mode after reaching the 2048 tile.
  - Animated score cards with real-time Best score updates.

## 📱 Screenshots

| Game Play | Game Over | Win Screen |
|---|---|---|
| ![Play](UI/Screenshots/1.png) | ![GameOver](UI/Screenshots/4.png) | ![Win](UI/Screenshots/2.png) |

## 🛠 Tech Stack

- **Framework:** [Flutter](https://flutter.dev)
- **Language:** Dart
- **Ads:** `google_mobile_ads`
- **Storage:** `shared_preferences`
- **Typography:** Rubik (Regular, SemiBold, Bold)

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (Latest Stable)
- Android Studio / Xcode
- AdMob Account

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/yourusername/game_2048.git
   cd game_2048
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **AdMob Configuration:**
   - Update `APPLICATION_ID` in `android/app/src/main/AndroidManifest.xml`.
   - Update `GADApplicationIdentifier` in `ios/Runner/Info.plist`.
   - Replace unit IDs in `lib/main.dart`.

4. **Run the app:**
   ```bash
   flutter run
   ```

## 🏗 Project Structure

```text
lib/
└── main.dart        # Primary game logic, UI, and AdMob lifecycle
android/             # Android specific configurations & Manifest
ios/                 # iOS specific configurations & Info.plist
UI/
├── Fonts/           # Rubik font assets
└── Screenshots/     # Visual references and mockups
```

## 📦 Building for Release

```bash
flutter build appbundle
```

The application uses the package name `com.aggab.numblock`. For more details on release signing and publishing, see the [Flutter deployment documentation](https://docs.flutter.dev/deployment/android).

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
