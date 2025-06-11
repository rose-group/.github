# Contributing to Rose Build

Thank you for your interest in contributing to Rose Build! This document provides guidelines and instructions for contributing.

## Code of Conduct

By participating in this project, you agree to abide by our Code of Conduct.

## How to Contribute

### Reporting Bugs

- Check if the bug has already been reported in the Issues section
- Use the bug report template when creating a new issue
- Include detailed steps to reproduce the bug
- Include expected and actual behavior
- Include screenshots if applicable
- Include your environment details (OS, Java version, Maven version)

### Suggesting Features

- Check if the feature has already been suggested in the Issues section
- Use the feature request template when creating a new issue
- Provide a clear and detailed description of the feature
- Explain why this feature would be useful
- Include any relevant examples or use cases

### Pull Requests

1. Fork the repository
2. Create a new branch for your feature/fix
3. Make your changes
4. Run the tests: `mvn clean verify`
5. Update documentation if necessary
6. Submit a pull request

### Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/rosestack/rose-build.git
   cd rose-build
   ```

2. Install dependencies:
   ```bash
   mvn clean install
   ```

3. Configure your IDE:
   - Import as Maven project
   - Enable EditorConfig support
   - Configure code style according to `.editorconfig`

### Code Style

- Follow the [Google Java Style Guide](https://google.github.io/styleguide/javaguide.html)
- Use EditorConfig for consistent coding style
- Run `mvn spotless:apply` to format code
- Run `mvn checkstyle:check` to verify code style

### Commit Messages

Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

Types:
- `feat`: A new feature
- `fix`: A bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code changes that neither fix bugs nor add features
- `perf`: Performance improvements
- `test`: Adding or fixing tests
- `chore`: Changes to the build process or auxiliary tools

### Testing

- Write unit tests for new features
- Ensure all tests pass: `mvn clean verify`
- Maintain or improve code coverage
- Run integration tests: `mvn verify -Pintegration`

### Documentation

- Update README.md if necessary
- Add Javadoc for new public APIs
- Update site documentation if necessary
- Keep CHANGELOG.md up to date

### Review Process

1. All pull requests require at least one review
2. CI checks must pass
3. Code coverage must not decrease
4. Documentation must be updated
5. Changes must follow the project's code style

### Release Process

1. Update version in pom.xml
2. Update CHANGELOG.md
3. Create a release tag
4. Deploy to Maven Central
5. Update documentation

## Getting Help

- Check the [documentation](https://rosestack.github.io/rose-build)
- Search existing issues
- Join our [community chat](https://github.com/rosestack/rose-build/discussions)

## License

By contributing to Rose Build, you agree that your contributions will be licensed under the project's [Apache License 2.0](LICENSE). 