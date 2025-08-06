import pytest
from ingestion.chunker import ChunkingConfig, SimpleChunker, DocumentChunk

def test_simple_chunker_short_content():
    config = ChunkingConfig(chunk_size=100, chunk_overlap=20, use_semantic_splitting=False)
    chunker = SimpleChunker(config)
    content = "This is a short text that should not be chunked."
    chunks = chunker.chunk_document(content, "Short Doc", "short.md")
    assert len(chunks) == 1
    assert chunks[0].content == content

def test_simple_chunker_long_content():
    config = ChunkingConfig(chunk_size=50, chunk_overlap=10, use_semantic_splitting=False)
    chunker = SimpleChunker(config)
    content = "This is a much longer sentence designed to test the basic chunking functionality and see if it splits correctly. This part should be in the second chunk."
    chunks = chunker.chunk_document(content, "Long Doc", "long.md")
    assert len(chunks) > 1
    # Check for overlap by seeing if the end of the first chunk is in the second
    end_of_first = chunks[0].content[-15:]
    assert end_of_first in chunks[1].content

def test_chunking_respects_paragraphs():
    config = ChunkingConfig(chunk_size=100, chunk_overlap=20, use_semantic_splitting=False)
    chunker = SimpleChunker(config)
    content = "First paragraph.\n\nSecond paragraph that is much longer and should definitely be its own chunk because of the paragraph break."
    chunks = chunker.chunk_document(content, "Paragraph Doc", "para.md")
    assert len(chunks) == 2
    assert chunks[0].content == "First paragraph."
    assert chunks[1].content.startswith("Second paragraph")

def test_document_chunk_metadata():
    config = ChunkingConfig(chunk_size=100, chunk_overlap=20)
    chunker = SimpleChunker(config)
    content = "This is a test."
    chunks = chunker.chunk_document(content, "Metadata Test", "meta.md", metadata={"custom": "value"})
    assert len(chunks) == 1
    chunk = chunks[0]
    assert chunk.metadata["title"] == "Metadata Test"
    assert chunk.metadata["source"] == "meta.md"
    assert chunk.metadata["custom"] == "value"
    assert chunk.metadata["chunk_method"] == "simple"
    assert chunk.metadata["total_chunks"] == 1
