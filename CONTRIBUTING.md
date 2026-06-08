# Contributing

Thank you for your interest in contributing to SpaceLiDAR.jl! This document provides guidelines and information for contributors.

## Reporting Issues

If you encounter a bug or have a problem with the software, please [open an issue](https://github.com/evetion/SpaceLiDAR.jl/issues/new) on GitHub. When reporting issues, please include:

- A clear and descriptive title.
- A minimal reproducible example (MRE) that demonstrates the problem (please share data that you're using as input)
- The version of SpaceLiDAR.jl you are using (`] status SpaceLiDAR` in the Julia REPL).
- Your Julia version (`versioninfo()`).
- Any relevant error messages or stack traces.

## Feature Requests

We welcome suggestions for new features or improvements. Please [open an issue](https://github.com/evetion/SpaceLiDAR.jl/issues/new) and describe:

- The feature you would like to see.
- The use case or problem it would solve.
- Any relevant references (papers, existing implementations, etc.).

## Contributing Code

### Getting Started

1. Fork the repository on GitHub.
2. Clone your fork locally:
   ```bash
   git clone https://github.com/your-username/SpaceLiDAR.jl.git
   ```
3. Create a new branch for your changes:
   ```bash
   git checkout -b my-feature-branch
   ```
4. Install the package in development mode. From the Julia REPL:
   ```julia
   ] dev .
   ```

### Making Changes

- Follow existing code style and conventions in the project.
- If you want to contribute a new data product, check the [ATL24 example](guides/new-schema.md).
- Add tests for new functionality in the `test/` directory.
- Add or update docstrings for any new or modified public functions.
- Run the test suite before submitting to make sure everything passes:
  ```julia
  ] test SpaceLiDAR
  ```

### Submitting a Pull Request

1. Push your branch to your fork on GitHub.
2. [Open a pull request](https://github.com/evetion/SpaceLiDAR.jl/compare) against the `main` branch.
3. Provide a clear description of your changes and reference any related issues.
4. Ensure that CI checks pass on your pull request.

## Seeking Support

If you have questions about using SpaceLiDAR.jl:

- Check the [documentation](https://evetion.github.io/SpaceLiDAR.jl/stable/).
- Search [existing issues](https://github.com/evetion/SpaceLiDAR.jl/issues) for similar questions.
- Open a new issue with the question label if your question is not answered elsewhere.
