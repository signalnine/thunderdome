"""Test image support in Anthropic provider.

Tests ImageBlock handling for vision capabilities (image understanding).
"""

import base64
from pathlib import Path

import pytest
from amplifier_core.message_models import ChatRequest
from amplifier_core.message_models import ImageBlock
from amplifier_core.message_models import Message
from amplifier_core.message_models import TextBlock

from amplifier_module_provider_anthropic import AnthropicProvider


@pytest.fixture
def test_image_base64():
    """Load test image and return base64 encoded data."""
    image_path = Path(__file__).parent / "assets" / "macbeth-witches-trio.jpg"
    with open(image_path, "rb") as f:
        image_data = f.read()
    return base64.b64encode(image_data).decode("utf-8")


@pytest.fixture
def anthropic_provider():
    """Create an AnthropicProvider instance for testing."""
    # Use test API key - provider will work without real key for _convert_messages
    return AnthropicProvider(api_key="test_key_for_unit_tests")


def test_image_block_conversion_to_anthropic_format(anthropic_provider, test_image_base64):
    """Test that ImageBlock in ChatRequest converts to Anthropic image format.
    
    This test verifies the core conversion logic:
    - ImageBlock with base64 source → Anthropic content array with image type
    - Text + Image in same message → multiple content blocks in correct order
    """
    # Create ChatRequest with text + image
    request = ChatRequest(
        messages=[
            Message(
                role="user",
                content=[
                    TextBlock(text="What do you see in this image?"),
                    ImageBlock(
                        source={
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": test_image_base64,
                        }
                    ),
                ],
            )
        ]
    )

    # Convert to Anthropic format
    anthropic_messages = anthropic_provider._convert_messages(
        [request.messages[0].model_dump()]
    )

    # Assert structure
    assert len(anthropic_messages) == 1  # One user message
    assert anthropic_messages[0]["role"] == "user"
    
    content = anthropic_messages[0]["content"]
    assert isinstance(content, list)
    assert len(content) == 2  # Text block + Image block

    # Assert text block
    assert content[0] == {"type": "text", "text": "What do you see in this image?"}

    # Assert image block (Anthropic format)
    assert content[1]["type"] == "image"
    assert content[1]["source"]["type"] == "base64"
    assert content[1]["source"]["media_type"] == "image/jpeg"
    assert content[1]["source"]["data"] == test_image_base64


def test_image_block_with_png(anthropic_provider):
    """Test ImageBlock with PNG mime type."""
    fake_png_data = base64.b64encode(b"fake_png_bytes").decode("utf-8")
    
    request = ChatRequest(
        messages=[
            Message(
                role="user",
                content=[
                    ImageBlock(
                        source={
                            "type": "base64",
                            "media_type": "image/png",
                            "data": fake_png_data,
                        }
                    ),
                    TextBlock(text="Describe this image"),
                ],
            )
        ]
    )

    anthropic_messages = anthropic_provider._convert_messages(
        [request.messages[0].model_dump()]
    )

    content = anthropic_messages[0]["content"]
    assert len(content) == 2
    
    # Image should come first (order preserved)
    assert content[0]["type"] == "image"
    assert content[0]["source"]["media_type"] == "image/png"
    assert content[0]["source"]["data"] == fake_png_data
    
    # Text should come second
    assert content[1] == {"type": "text", "text": "Describe this image"}


def test_multiple_images_in_message(anthropic_provider):
    """Test handling multiple ImageBlocks in a single message."""
    fake_data_1 = base64.b64encode(b"image1").decode("utf-8")
    fake_data_2 = base64.b64encode(b"image2").decode("utf-8")
    
    request = ChatRequest(
        messages=[
            Message(
                role="user",
                content=[
                    TextBlock(text="Compare these images:"),
                    ImageBlock(
                        source={
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": fake_data_1,
                        }
                    ),
                    ImageBlock(
                        source={
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": fake_data_2,
                        }
                    ),
                ],
            )
        ]
    )

    anthropic_messages = anthropic_provider._convert_messages(
        [request.messages[0].model_dump()]
    )

    content = anthropic_messages[0]["content"]
    assert len(content) == 3  # Text + 2 images
    
    assert content[0] == {"type": "text", "text": "Compare these images:"}
    assert content[1]["type"] == "image"
    assert content[1]["source"]["data"] == fake_data_1
    assert content[2]["type"] == "image"
    assert content[2]["source"]["data"] == fake_data_2


def test_text_only_message_still_works(anthropic_provider):
    """Ensure text-only messages still work after ImageBlock support added."""
    request = ChatRequest(
        messages=[
            Message(
                role="user",
                content=[TextBlock(text="Hello, how are you?")],
            )
        ]
    )

    anthropic_messages = anthropic_provider._convert_messages(
        [request.messages[0].model_dump()]
    )

    content = anthropic_messages[0]["content"]
    assert isinstance(content, list)
    assert len(content) == 1
    assert content[0] == {"type": "text", "text": "Hello, how are you?"}


@pytest.mark.asyncio
async def test_image_vision_integration_with_real_api(test_image_base64):
    """Integration test: Verify ImageBlock works with real Anthropic API.
    
    This test validates end-to-end image understanding:
    - ImageBlock → Anthropic API format conversion
    - Real API call with vision
    - Response parsing
    
    Requires ANTHROPIC_API_KEY environment variable.
    Skip if not available (unit tests still validate conversion logic).
    """
    import os
    
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        pytest.skip("ANTHROPIC_API_KEY not set - skipping integration test")
    
    # Create provider with real API key
    provider = AnthropicProvider(api_key=api_key)
    
    # Create request with image of Macbeth stage production
    request = ChatRequest(
        messages=[
            Message(
                role="user",
                content=[
                    TextBlock(text="Describe this image in detail. What do you see?"),
                    ImageBlock(
                        source={
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": test_image_base64,
                        }
                    ),
                ],
            )
        ]
    )

    # Call the real API
    response = await provider.complete(request)

    # Verify response structure
    assert response is not None
    assert response.content is not None
    assert len(response.content) > 0
    
    # Extract text from response
    response_text = ""
    for block in response.content:
        if hasattr(block, "type") and block.type == "text":
            response_text += block.text
    
    # Verify the model actually saw the image and understood it
    # The test image contains specific elements we can check for
    response_lower = response_text.lower()
    
    # Should mention it's a stage production/theatrical scene
    assert any(keyword in response_lower for keyword in ["stage", "theater", "theatre", "production", "performance"]), \
        f"Expected stage/theater reference in response: {response_text[:200]}"
    
    # Should recognize the witches/women
    assert any(keyword in response_lower for keyword in ["witch", "women", "woman", "people", "person", "figure"]), \
        f"Expected people/witches reference in response: {response_text[:200]}"
    
    # Should mention Macbeth or the text visible in the image
    assert any(keyword in response_lower for keyword in ["macbeth", "text", "act", "scene"]), \
        f"Expected Macbeth/text reference in response: {response_text[:200]}"
    
    print(f"\n✅ Vision test passed! Model response:\n{response_text[:500]}...")
