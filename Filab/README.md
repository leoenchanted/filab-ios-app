# Film Lab iOS

A professional film simulation app for iOS, built with SwiftUI and Metal. This app brings the classic look of analog film stocks to your digital photos with GPU-accelerated processing.

## Features

### Film Presets
- **Kodak Portra 400** - Portrait photography favorite with skin tone protection
- **Kodak Gold 200** - Warm, nostalgic tones
- **Fuji Pro 400H** - Japanese "airy" look with lifted highlights
- **Fuji Velvia 50** - High saturation landscape film
- **CineStill 800T** - Cinematic tungsten film with signature red halation
- **CineStill 50D** - Daylight cinema film
- **Ilford HP5 Plus** - Classic high-contrast black & white
- **Ilford Delta 3200** - High-speed B&W with heavy grain
- **Polaroid** - Vintage instant film look with fade
- **Kodachrome** - Legendary vivid color film
- **Ricoh GR** - Positive film mode simulation
- **Lomography** - Experimental look with color shifts

### Adjustments
- **Strength** - Film effect intensity (0-100%)
- **Exposure** - Brightness adjustment (-50 to +50)
- **Contrast** - S-curve contrast (-50 to +50)
- **Highlights** - Highlight recovery (-50 to +50)
- **Shadows** - Shadow lift (-50 to +50)
- **Temperature** - Warm/cool adjustment (-50 to +50)
- **Tint** - Green/magenta shift (-50 to +50)
- **Saturation** - Color intensity (-50 to +50)
- **Vignette** - Edge darkening (0-100)
- **Grain** - Film grain intensity (0-100)

### Technical Features
- GPU-accelerated processing using Metal
- Real-time preview with Core Image fallback
- Split-screen comparison view
- Full-resolution export
- Modern SwiftUI interface with adaptive layout

## Project Structure

```
FilmLab/
├── App/
│   ├── FilabApp.swift            # App entry point
│   └── ContentView.swift         # Root tabs and editor presentation
├── Features/
│   ├── Camera/                   # Dedicated camera entry and viewfinder UI
│   ├── Library/                  # Photo import, album, history management
│   ├── Editor/                   # Film presets, adjustments, export, compare
│   └── Settings/                 # Appearance, export, cache preferences
├── Core/
│   ├── Appearance/               # Theme and color scheme state
│   ├── Film/                     # Film preset and adjustment models
│   ├── History/                  # Local edit history store
│   └── Rendering/                # Metal processor and shader pipeline
├── Assets.xcassets/              # App icons and assets
└── Preview Content/              # Preview assets
```

## Technology Stack

- **SwiftUI** - Modern declarative UI framework
- **Metal** - GPU-accelerated image processing
- **Core Image** - Fallback processing and filters
- **MetalKit** - Texture loading and management
- **PhotosUI** - Photo picker integration

## Film Simulation Techniques

### 1. Color Matrix Transformation
Each film preset uses a 3x3 color matrix to remap RGB channels, creating the unique color signature of each film stock.

### 2. Tone Curves
Non-linear tone curves control how different brightness regions are mapped, creating film's characteristic "toe" and "shoulder" response.

### 3. Halation (CineStill)
Simulates the red/orange bloom around bright highlights by:
- Extracting highlight regions
- Applying gaussian blur with color shift
- Blending back with original image

### 4. Spectral Grain
Multi-octave noise generation creates natural film grain:
- High-frequency noise for fine grain
- Low-frequency noise for coarse structure
- Luminance-based mixing (more grain in shadows)

### 5. Vignette & Fade
- Vignette: Edge darkening typical of lens optics
- Fade: Simulates film base fog for vintage looks

## Building and Running

### Requirements
- Xcode 15.0+
- iOS 17.0+
- Metal-capable device (iPhone XS or later recommended)

### Build Instructions
1. Open `FilmLab.xcodeproj` in Xcode
2. Select your target device or simulator
3. Build and run (⌘+R)

### Device Recommendation
For best performance with Metal shaders:
- iPhone XS/XR or newer
- iPad Pro (any generation)
- iPad Air (4th gen or newer)

## Usage

1. **Import Photo**: Tap the photo icon to import from your library
2. **Select Film**: Choose a film preset from the bottom strip
3. **Adjust**: Fine-tune the effect with adjustment sliders
4. **Compare**: Long-press the image or tap compare button for split-screen
5. **Export**: Tap share icon to save or share

## Performance

- Metal processing: ~16-33ms for 4K images (real-time)
- Core Image fallback: ~100-300ms depending on image size
- Grain generation uses temporal randomization for natural look

## Credits

Film simulations based on characteristics of actual film stocks:
- Kodak Portra, Gold - Eastman Kodak Company
- Fuji Pro, Velvia - FUJIFILM Corporation
- CineStill - CineStill Film
- Ilford HP5, Delta - Ilford Photo

## License

This project is created for educational purposes based on film photography characteristics.

---

Built with SwiftUI and Metal. Film your world.
