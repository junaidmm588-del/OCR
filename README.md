# PDF-OCR 2.0 (Portable Searchable PDF Converter)
**Created by Junead Mansoori**

A 100% offline, standalone Windows utility that converts scanned PDFs into searchable, selectable PDFs using parallel OCR processing.

## Key Features
* **100% Offline & Private:** Zero cloud uploads, zero telemetry, and no internet connection required at runtime.
* **Truly Portable:** Single `.exe` file. No installation and no administrator rights needed.
* **Fast Multithreading:** Processes multiple pages simultaneously across your CPU cores.
* **Smart Pre-processing:** Automatically skips blank pages, trims empty margins, and preserves existing text layers.
* **Multi-Language Support:** Built-in support for English, Hindi, Marathi, Arabic, Russian, Chinese (Simplified), Japanese, and Spanish.

## How to Use
1. Download **`PDF-OCR.exe`**.
2. Double-click `PDF-OCR.exe` to launch the app (or drag-and-drop your PDF files directly onto the `.exe`).
3. *Note on Windows SmartScreen:* Because this is a free open-source executable without a paid corporate signing certificate, Windows Defender may show a **"Windows protected your PC"** prompt on first launch. Click **"More info"** -> **"Run anyway"**.
4. Select your document languages and click **Start OCR**. Your searchable file will be saved right next to the original as `<filename>_ocr.pdf`.

## Building from Source
The complete source code and portable builder are contained inside **`Create-PDF-OCR.bat`**. Running `Create-PDF-OCR.bat --rebuild` on any Windows PC will automatically extract the embedded Python source and compile a fresh `PDF-OCR.exe`.

## License & Open-Source Credits
This software is free and distributed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**.
* **PyMuPDF:** Used for PDF rendering and text layer merging (Licensed under GNU AGPL v3.0).
* **Tesseract OCR:** Used for optical character recognition (Licensed under Apache License 2.0).

*Disclaimer: This software is provided "as-is", without warranty of any kind, express or implied.*
