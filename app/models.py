from pydantic import BaseModel, Field
from typing import List, Optional

class ModelSpec(BaseModel):
    """Specification for a single open source model."""
    name: str
    path: str
    description: Optional[str] = None
    weight: float = Field(1.0, ge=0)

class EnsembleConfig(BaseModel):
    """Configuration for an ensemble of models."""
    models: List[ModelSpec]
    strategy: str = "weighted"

    def weights(self) -> List[float]:
        total = sum(m.weight for m in self.models)
        if total == 0:
            return [1 / len(self.models)] * len(self.models)
        return [m.weight / total for m in self.models]

class Prediction(BaseModel):
    """Container for model predictions."""
    model: str
    output: str
    score: Optional[float] = None
