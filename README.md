# SoftBridge Texts 📱

**SoftBridge Texts** is a modern, feature-rich, and secure SMS management application built with Flutter and Native Android integration. Designed for speed and cleanliness, it provides a superior alternative to default messaging apps with advanced organization and security features.

---

## ✨ Key Features

### 📂 Organization & Productivity
*   **Custom Folders:** Create your own folders (e.g., Work, Finance, Family) and move entire conversations into them for better organization.
*   **Nested Senders:** Inside each folder, messages are automatically grouped by sender.
*   **Pin Conversations:** Keep your most important chats at the very top.
*   **Message Records:** A built-in "notebook" to save reusable message templates. Tap a record to immediately pre-fill a new message.
*   **Bulk Actions:** Long-press to enter selection mode. Select multiple (or all) conversations to delete, pin, or block in one go.

### 🛡️ Security & Privacy
*   **OTP Highlighting:** Automated detection of One-Time Passwords (OTPs) with a specialized notification style and a "Copy Code" button.
*   **Auto-Delete OTPs:** Set a timer (e.g., 10 minutes) to automatically remove OTP messages and keep your inbox clean.
*   **Spam Protection:** On-device heuristic filtering to hide suspected spam messages.
*   **Link Protection:** External links are disabled by default. When enabled, a security alert confirms you trust the source before opening the browser.
*   **Block Contacts:** Easily block unwanted senders. Blocked contacts are hidden and won't trigger notifications.

### 🎨 Personalization & UI
*   **Calm Design:** A clean, card-based interface with generous spacing for a stress-free experience.
*   **Dark Mode:** Full support for a beautiful dark theme that respects system settings.
*   **Global Font Scaling:** Adjust text size (Small, Medium, Large) across the entire app instantly from settings.
*   **Interactive Notifications:** High-importance notifications that let you jump directly into the correct conversation.

---

## 🛠️ Technical Overview

*   **Framework:** [Flutter](https://flutter.dev)
*   **Language:** Dart & Kotlin
*   **Native Integration:** Uses `MethodChannel` for deep Android system interaction (Content Providers, SMS Receivers, and Default App Roles).
*   **Database:** Android System SMS Provider (ensures your messages stay in sync with the system).
*   **Storage:** `SharedPreferences` for app-specific settings and folder metadata.

---

## 🚀 Getting Started

### Prerequisites
*   Android SDK 33+
*   Flutter Stable Channel

### Installation
1.  **Clone the repository:**
    ```bash
    git clone https://github.com/yourusername/text.git
    ```
2.  **Clean and fetch dependencies:**
    ```bash
    flutter clean
    flutter pub get
    ```
3.  **Run the application:**
    ```bash
    flutter run
    ```

### ⚠️ Important Note
To fully utilize all features (sending, deleting, and marking as read), **SoftBridge Texts** must be set as your **Default SMS Application**. The app will prompt you to do this upon first launch.

---

## 🏗️ Project Structure
*   `lib/main.dart`: Global state management and app entry.
*   `lib/screens/`: Individual feature pages (Message List, Conversation, Folders, Records, etc.).
*   `lib/notification_service.dart`: Handles high-priority alerts and OTP styles.
*   `android/app/src/main/kotlin/`: Native Kotlin implementation for SMS broadcast receivers and system-level operations.

---

## 📜 License
© 2025 SoftBridge Labs. Designed for performance and privacy.
