import pytest

# Note: The repository appears to use pytest for testing.
# Testing library/framework: pytest

# Import the classes from the provided module under test.
# The code to test is in tests/test_models.py (provided in the PR diff),
# so we import from tests.test_models.
from tests.test_models import ModelSpec, EnsembleConfig, Prediction
from pydantic import ValidationError


class TestModelSpec:
    def test_modelspechappy_minimal_required_fields(self):
        m = ModelSpec(name="m1", path="/models/m1")
        assert m.name == "m1"
        assert m.path == "/models/m1"
        # Optional defaults
        assert m.description is None
        assert m.weight == 1.0

    def test_modelspec_with_description_and_custom_weight(self):
        m = ModelSpec(name="m2", path="/models/m2", description="A model", weight=2.5)
        assert m.description == "A model"
        assert m.weight == 2.5

    def test_modelspec_weight_cannot_be_negative(self):
        with pytest.raises(ValidationError) as ei:
            ModelSpec(name="bad", path="/models/bad", weight=-0.0001)
        msg = str(ei.value)
        assert "ensure this value is greater than or equal to 0" in msg or "ge" in msg

    def test_modelspec_missing_required_name(self):
        with pytest.raises(ValidationError) as ei:
            ModelSpec(path="/models/missing-name")  # type: ignore
        assert "name" in str(ei.value)

    def test_modelspec_missing_required_path(self):
        with pytest.raises(ValidationError) as ei:
            ModelSpec(name="missing-path")  # type: ignore
        assert "path" in str(ei.value)

    def test_modelspec_weight_boundary_zero_ok(self):
        m = ModelSpec(name="zero", path="/models/zero", weight=0.0)
        assert m.weight == 0.0

    def test_modelspec_weight_large_float(self):
        large = 1e18
        m = ModelSpec(name="big", path="/models/big", weight=large)
        assert m.weight == large


class TestEnsembleConfigWeights:
    def test_weights_single_model_default_weight(self):
        e = EnsembleConfig(models=[ModelSpec(name="m1", path="p1")])
        weights = e.weights()
        assert weights == [1.0]

    def test_weights_two_models_default_weights_normalize_evenly(self):
        e = EnsembleConfig(models=[
            ModelSpec(name="m1", path="p1"),  # 1.0
            ModelSpec(name="m2", path="p2"),  # 1.0
        ])
        weights = e.weights()
        assert len(weights) == 2
        assert weights[0] == pytest.approx(0.5, rel=1e-12, abs=1e-12)
        assert weights[1] == pytest.approx(0.5, rel=1e-12, abs=1e-12)
        assert sum(weights) == pytest.approx(1.0, rel=1e-12, abs=1e-12)

    def test_weights_custom_weights_normalization(self):
        e = EnsembleConfig(models=[
            ModelSpec(name="m1", path="p1", weight=2.0),
            ModelSpec(name="m2", path="p2", weight=1.0),
            ModelSpec(name="m3", path="p3", weight=3.0),
        ])
        weights = e.weights()
        total = 2.0 + 1.0 + 3.0
        expected = [2.0/total, 1.0/total, 3.0/total]
        assert len(weights) == 3
        for w, exp in zip(weights, expected):
            assert w == pytest.approx(exp, rel=1e-12, abs=1e-12)
        assert sum(weights) == pytest.approx(1.0, rel=1e-12, abs=1e-12)

    def test_weights_all_zero_weights_uniform_distribution(self):
        e = EnsembleConfig(models=[
            ModelSpec(name="m1", path="p1", weight=0.0),
            ModelSpec(name="m2", path="p2", weight=0.0),
            ModelSpec(name="m3", path="p3", weight=0.0),
            ModelSpec(name="m4", path="p4", weight=0.0),
        ])
        weights = e.weights()
        assert weights == [0.25, 0.25, 0.25, 0.25]
        assert sum(weights) == pytest.approx(1.0, rel=1e-12, abs=1e-12)

    def test_weights_mixture_zero_and_nonzero(self):
        e = EnsembleConfig(models=[
            ModelSpec(name="a", path="pa", weight=0.0),
            ModelSpec(name="b", path="pb", weight=2.0),
            ModelSpec(name="c", path="pc", weight=0.0),
        ])
        weights = e.weights()
        # total = 2.0 (zeros contribute 0)
        assert weights[0] == pytest.approx(0.0, rel=1e-12, abs=1e-12)
        assert weights[1] == pytest.approx(1.0, rel=1e-12, abs=1e-12)
        assert weights[2] == pytest.approx(0.0, rel=1e-12, abs=1e-12)
        assert sum(weights) == pytest.approx(1.0, rel=1e-12, abs=1e-12)

    def test_weights_order_preservation(self):
        e = EnsembleConfig(models=[
            ModelSpec(name="first", path="p1", weight=1.0),
            ModelSpec(name="second", path="p2", weight=3.0),
            ModelSpec(name="third", path="p3", weight=6.0),
        ])
        weights = e.weights()
        # Ensure order corresponds to model order
        assert weights[0] < weights[1] < weights[2]

    def test_weights_extreme_values_numeric_stability(self):
        tiny = 1e-18
        huge = 1e18
        e = EnsembleConfig(models=[
            ModelSpec(name="tiny", path="pt", weight=tiny),
            ModelSpec(name="huge", path="ph", weight=huge),
        ])
        weights = e.weights()
        total = tiny + huge
        expected = [tiny/total, huge/total]
        assert weights[0] == pytest.approx(expected[0], rel=1e-12, abs=1e-30)
        assert weights[1] == pytest.approx(expected[1], rel=1e-12, abs=1e-12)
        assert sum(weights) == pytest.approx(1.0, rel=1e-12, abs=1e-12)

    def test_weights_strategy_default_value_present(self):
        # Not directly used by weights(), but we validate default field exists
        e = EnsembleConfig(models=[ModelSpec(name="m", path="p")])
        assert e.strategy == "weighted"


class TestPrediction:
    def test_prediction_minimal_required_fields(self):
        p = Prediction(model="m1", output="ok")
        assert p.model == "m1"
        assert p.output == "ok"
        assert p.score is None

    def test_prediction_with_score(self):
        p = Prediction(model="m2", output="value", score=0.87)
        assert isinstance(p.score, float)
        assert p.score == 0.87

    def test_prediction_invalid_missing_required(self):
        with pytest.raises(ValidationError):
            Prediction(output="value")  # type: ignore

        with pytest.raises(ValidationError):
            Prediction(model="m", score=0.1)  # type: ignore

    def test_prediction_score_allows_none_and_rejects_non_numeric(self):
        # None is allowed (Optional[float])
        p = Prediction(model="m", output="o", score=None)
        assert p.score is None

        # Non-numeric rejected
        with pytest.raises(ValidationError):
            Prediction(model="m", output="o", score="high")  # type: ignore

    def test_prediction_output_and_model_strict_types(self):
        with pytest.raises(ValidationError):
            Prediction(model=123, output="x")  # type: ignore

        with pytest.raises(ValidationError):
            Prediction(model="m", output=456)  # type: ignore