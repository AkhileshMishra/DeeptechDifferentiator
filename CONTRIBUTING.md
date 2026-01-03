# Contributing to Healthcare Imaging MLOps Platform

Thank you for your interest in contributing to the Healthcare Imaging MLOps Platform! This document provides guidelines and instructions for contributing.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Pull Request Process](#pull-request-process)
- [Coding Standards](#coding-standards)
- [Testing Guidelines](#testing-guidelines)

## Code of Conduct

This project adheres to a Code of Conduct. By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Set up the development environment
4. Create a feature branch
5. Make your changes
6. Submit a pull request

## Development Setup

### Prerequisites

- Python 3.11+
- Terraform 1.6+
- Docker
- AWS CLI configured with appropriate credentials
- Git

### Local Setup

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/DeeptechDifferentiator.git
cd DeeptechDifferentiator

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r python/requirements.txt

# Install development dependencies
pip install black flake8 isort mypy pytest pytest-cov

# Initialize Terraform (for validation)
cd terraform
terraform init -backend=false
```

## Making Changes

### Branch Naming Convention

- `feature/` - New features
- `bugfix/` - Bug fixes
- `hotfix/` - Critical fixes for production
- `docs/` - Documentation updates
- `refactor/` - Code refactoring

Example: `feature/add-model-versioning`

### Commit Messages

Follow the conventional commits specification:

```
type(scope): description

[optional body]

[optional footer]
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Formatting
- `refactor`: Code refactoring
- `test`: Adding tests
- `chore`: Maintenance

Example:
```
feat(pipeline): add model versioning support

- Implement version tracking in DynamoDB
- Add version comparison in evaluation step
- Update deployment to use versioned models

Closes #123
```

## Pull Request Process

1. **Update Documentation**: Ensure README and relevant docs are updated
2. **Add Tests**: Include tests for new functionality
3. **Run Linters**: Ensure code passes all quality checks
4. **Update CHANGELOG**: Add entry for your changes
5. **Request Review**: Tag appropriate reviewers

### PR Checklist

- [ ] Code follows project style guidelines
- [ ] Tests pass locally
- [ ] Documentation updated
- [ ] CHANGELOG updated
- [ ] No sensitive data in commits
- [ ] Terraform validates successfully

## Coding Standards

### Python

- Follow PEP 8 style guide
- Use type hints
- Maximum line length: 120 characters
- Use docstrings for all public functions

```python
def process_image(
    image_path: str,
    target_size: tuple[int, int] = (512, 512)
) -> np.ndarray:
    """
    Process a DICOM image for model input.
    
    Args:
        image_path: Path to the DICOM file
        target_size: Target dimensions (height, width)
        
    Returns:
        Preprocessed image array
        
    Raises:
        FileNotFoundError: If image file doesn't exist
    """
    ...
```

### Terraform

- Use consistent naming: `resource_type_name`
- Add descriptions to all variables
- Use modules for reusable components
- Include tags on all resources

```hcl
variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}
```

### Docker

- Use multi-stage builds when possible
- Pin base image versions
- Include health checks
- Minimize image size

## Testing Guidelines

### Unit Tests

```bash
# Run all tests
pytest python/tests/ -v

# Run with coverage
pytest python/tests/ -v --cov=src --cov-report=html

# Run specific test file
pytest python/tests/test_preprocessing.py -v
```

### Integration Tests

```bash
# Run integration tests (requires AWS credentials)
pytest python/tests/integration/ -v --integration
```

### Terraform Tests

```bash
# Validate Terraform configuration
cd terraform
terraform validate

# Check formatting
terraform fmt -check -recursive
```

## Questions?

If you have questions, please:
1. Check existing issues and documentation
2. Open a new issue with the question label
3. Reach out to maintainers

Thank you for contributing!
