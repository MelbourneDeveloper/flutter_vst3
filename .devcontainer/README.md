# VST Development Container

This dev container provides a complete development environment for the VST project with all dependencies pre-installed.

## What's Included

- **Ubuntu 22.04** base image
- **CMake 3.22+** for building C++ components
- **Dart SDK** for Dart development
- **Flutter SDK** for Flutter UI development
- **VST3 SDK directory** prepared (you need to provide the SDK)
- **Build tools** (GCC, Make, etc.)
- **Audio development libraries** (ALSA, X11, etc.)
- **Node.js and npm** for package management
- **Claude Code** pre-installed globally

## Usage

### With VS Code

1. Install the **Dev Containers** extension in VS Code
2. Open this project folder in VS Code
3. Click "Reopen in Container" when prompted (or use Command Palette: "Dev Containers: Reopen in Container")
4. Wait for the container to build (first time takes ~5-10 minutes)
5. Once ready, you can use the terminal to run:
   ```bash
   make build    # Build everything
   make test     # Run tests
   make help     # See all available commands
   ```

### Environment Variables

The container automatically sets:
- `VST3_SDK_DIR=/opt/vst3sdk` - Points to the pre-installed Steinberg VST3 SDK
- `PATH` includes Dart and Flutter binaries

### Verification

After the container starts, run:
```bash
make check-env
```

This should show all dependencies as available.

## Container Features

- **Persistent workspace**: Your code changes are preserved
- **Pre-configured extensions**: Dart, Flutter, C++, CMake support
- **Port forwarding**: Ports 3000 and 8080 forwarded for development servers
- **Git integration**: Git is available and configured

## Troubleshooting

If the container fails to build:
1. Ensure Docker is running
2. Ensure you have the VST3 SDK available (see VST3 SDK Setup below)
3. Try rebuilding: Command Palette → "Dev Containers: Rebuild Container"

## VST3 SDK Setup

The VST3 SDK is not automatically downloaded due to Steinberg's licensing requirements. You need to:

1. Download the VST3 SDK from [Steinberg's Developer Portal](https://www.steinberg.net/developers/)
2. Extract it and place the `vst3sdk` folder in your project root
3. The container will automatically mount it to `/opt/vst3sdk`

Alternatively, you can modify the devcontainer to mount your SDK from elsewhere on your system.