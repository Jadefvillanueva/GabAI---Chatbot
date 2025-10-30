# GabAI Student Helper

![Built with Flutter](https://img.shields.io/badge/Built%20with-Flutter-02569B?logo=flutter)

A mobile chatbot application built with Flutter. "GabAI Student Helper" provides a clean, modern interface for students to ask questions and get real-time answers from a conversational AI backend powered by Botpress.

## ✨ Features

- **Animated Splash Screen:** A smooth, scaling animation on app launch.
- **Modern Chat UI:** A clean and readable chat interface with distinct user and AI message bubbles.
- **Real-time Communication:** Uses WebSockets for instant message delivery and receiving.
- **Typing Indicator:** Shows a "GabAI is typing..." animation when the bot is processing a response.
- **Prompt Suggestions:** An empty-state screen that suggests common questions (e.g., "How do I apply for financial aid?") to help users get started.
- **Backend Integration:** Fully wired to a Botpress service for conversation logic.
- **Configuration-Based:** Uses a `.env` file to manage API and WebSocket URLs.

## 📱 Screenshots

_(Add your screenshots here!)_

| Splash Screen | Chat (Empty) | Chat (Conversation) |
| :-----------: | :----------: | :-----------------: |
|               |              |                     |

## 🚀 Getting Started

To run this project locally, follow these steps:

### 1. Prerequisites

- You must have the [Flutter SDK](https://flutter.dev/docs/get-started/install) installed.
- You must have a running [Botpress](https://botpress.com/) instance accessible via HTTP and WebSocket URLs.

### 2. Installation & Setup

1.  **Clone the repository:**

    ```sh
    git clone [https://github.com/YOUR_USERNAME/YOUR_REPOSITORY_NAME.git](https://github.com/YOUR_USERNAME/YOUR_REPOSITORY_NAME.git)
    cd YOUR_REPOSITORY_NAME
    ```

2.  **Create a `.env` file:**
    In the root of the project, create a file named `.env` and add your Botpress URLs:

    ```.env
    BOTPRESS_BASE_URL=[https://your-botpress-instance.com/api/v1](https://your-botpress-instance.com/api/v1)
    BOTPRESS_WEBSOCKET_URL=wss://[your-botpress-instance.com/socket.io/](https://your-botpress-instance.com/socket.io/)
    ```

3.  **Install dependencies:**

    ```sh
    flutter pub get
    ```

4.  **Run the app:**
    ```sh
    flutter run
    ```

## 🛠️ Technology Stack

- **Frontend:** Flutter & Dart
- **Backend Service:** [Botpress](https://botpress.com/)
- **Key Packages:**
  - `http`: For initial API calls (create user/conversation).
  - `web_socket_channel`: For real-time chat communication.
  - `flutter_dotenv`: For managing environment variables.
  - `google_fonts`: For custom app-wide fonts.
  - `flutter_spinkit`: For the bot typing indicator.
