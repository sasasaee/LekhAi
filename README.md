# LekhAi

LekhAi is a **Flutter-based accessibility application** designed to empower **visually impaired and motor-disabled students** to navigate educational content and complete exams independently. It combines **advanced voice commands**, **Text-to-Speech (TTS)**, and **intelligent document scanning** to provide a seamless, hands-free experience for reading PDFs and taking exams.

## Features

LekhAi allows users to **take exams, read documents, and manage study materials hands-free**, effectively **replacing human scribes**. It serves as a **unified digital exam platform** specifically tailored for **students with visual or motor impairments**, enabling them to perform study and exam tasks independently and efficiently.

### 🌟 Quick Overview
* **Take Exams:** Scan question papers, answer via typing or voice.  
* **Read PDFs Aloud:** Text-to-Speech for pages, sentences, or exam content.  
* **Saved Papers:** Archive, search, and export past papers.  
* **Voice Commands:** Full app control using the wake word **“Hey LekhAi”**.  
* **Accessibility-First:** Haptic feedback, spoken navigation, and simplified single-tap mode.  

### 📌 Detailed Features

#### 🎓 Core Exam Functionality – “Take Exam”
* **Paper Scanning:** Import papers via camera or gallery.  
* **Smart OCR with Gemini AI:** Extracts and structures text automatically.  
* **Flexible Answering:** Type or answer hands-free with voice dictation.  
* **Exam Management:** Set durations, limits, and manage student info.  

#### 📖 PDF & Document Reader
* **Read Aloud (TTS):** Entire pages or selected sentences.  
* **Smart Navigation:** Jump to pages via touch or voice.  
* **Viewing Controls:** Zoom in/out or reset document view.  

#### 🗄️ Records & History – “Saved Papers”
* **Archive & Review:** Save papers with answers.  
* **History Management:** Delete individual papers or clear all.  
* **Export & Share:** Share or export PDFs easily.  
* **Search:** Locate previous papers quickly.  

#### 🎙️ Advanced Hands-Free Voice Commands
Powered by **Picovoice (Porcupine & Rhino)**:  
* **Navigation:** “Go to Take Exam”, “Show saved papers”, etc.  
* **Scrolling & Media Control:** “Next page”, “Read this page”, adjust volume.  
* **Dialog Interaction:** Respond hands-free with “Yes”, “No”, or options.  

#### 🦯 Accessibility-First Design
* **Haptic Feedback:** Vibration cues for actions.  
* **Spoken Navigation:** Full UI narration.  
* **Single Tap Mode:** Simplified one-tap interaction.  

#### ⚙️ Customization & Settings
* Toggle haptics, voice commands, or single-tap mode.  
* Securely input **Gemini API** and **Picovoice keys**.  
* Offline fallback: switch between local and cloud processing.  

---

## Prerequisites

Before running the project, ensure you have:

1. **Flutter SDK**: Version `^3.10.1` or higher.  
2. **API Keys**:  
   * **Picovoice Access Key** – for wake word and voice commands. Get a free key from [Picovoice Console](https://console.picovoice.ai/).  
   * **Gemini API Key** – for OCR and AI processing. Get a key from [Google AI Studio](https://aistudio.google.com/).  

---

## Step-by-Step Description of How to Run the Project

**Step 1. Clone the project and navigate to the directory**
```bash
# If you are pulling from a repository
git clone https://github.com/sasasaee/LekhAi.git
cd LekhAi
```

**Step 2. Install dependencies**
Fetch all the necessary Flutter packages defined in `pubspec.yaml` by running:
```bash
flutter pub get
```

**Step 3. Run the application**
Connect a physical device or start an Android/iOS emulator, then run:
```bash
flutter run
```
*Note: Since this application relies heavily on microphone usage for Voice Commands and Voice Dictation, it is highly recommended to test it on a **Real Physical Device** rather than an emulator.*

**Step 4. Configure your API Keys inside the App**
1. Once the app launches on your device, navigate to the **Preferences** (Settings) page.
2. Enter your **Picovoice Access Key** (and Gemini API key, if applicable) in the provided settings fields.
3. Make sure the toggle for Voice Commands is enabled.

## Using Voice Commands

LekhAi uses the wake word **“Hey LekhAi”** to start listening for intents. You can control almost all aspects of the app hands-free. Supported commands include:

### **Navigation**
* `Go to Take Exam`  
* `Show saved papers`  
* `Navigate to settings`  

### **Scrolling & Media Control**
* `Scroll up` / `Scroll down`  
* `Next page` / `Previous page`  
* `Read this page` / `Stop speaking`  
* `Turn up volume` / `Turn down volume`  

### **Dialog Interaction**
* `Yes` / `No`  
* `Choose option 1` / `Choose option 2` / `Choose option 3`  

> **Note:** A full list of supported voice commands is available in the `Lekhai_Commands.yml` file in the root directory.
