"""Structural validation tests for anthropic provider.

Inherits authoritative tests from amplifier-core.
"""

from amplifier_core.validation.structural import ProviderStructuralTests
from amplifier_module_provider_anthropic import AnthropicProvider


class TestAnthropicProviderStructural(ProviderStructuralTests):
    """Run standard provider structural tests for anthropic.

    All tests from ProviderStructuralTests run automatically.
    Add module-specific structural tests below if needed.
    """


class TestBaseUrlConfigField:
    """Tests for base_url ConfigField declaration."""

    def test_base_url_config_field_declared(self):
        """Test that base_url ConfigField is properly declared in get_info()."""
        provider = AnthropicProvider("test-api-key", {})
        info = provider.get_info()

        # Find the base_url config field
        base_url_field = next(
            (f for f in info.config_fields if f.id == "base_url"),
            None,
        )

        assert base_url_field is not None, "base_url ConfigField should be declared"
        assert base_url_field.display_name == "API Base URL"
        assert base_url_field.field_type == "text"
        assert base_url_field.required is False

    def test_base_url_config_field_has_env_var(self):
        """Test that base_url ConfigField declares ANTHROPIC_BASE_URL env var."""
        provider = AnthropicProvider("test-api-key", {})
        info = provider.get_info()

        base_url_field = next(
            (f for f in info.config_fields if f.id == "base_url"),
            None,
        )

        assert base_url_field is not None
        assert base_url_field.env_var == "ANTHROPIC_BASE_URL"

    def test_base_url_config_field_has_default(self):
        """Test that base_url ConfigField has default value."""
        provider = AnthropicProvider("test-api-key", {})
        info = provider.get_info()

        base_url_field = next(
            (f for f in info.config_fields if f.id == "base_url"),
            None,
        )

        assert base_url_field is not None
        assert base_url_field.default == "https://api.anthropic.com"
