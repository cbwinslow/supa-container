# Use a specific, stable version of Python for reproducibility
FROM python:3.10.13-slim-bookworm

# Set environment variables to prevent Python from writing .pyc files
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org && \
    pip install --no-cache-dir -r requirements.txt --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org

# Copy the application code
COPY . .

# The FastAPI application entrypoint
CMD ["uvicorn", "api:app", "--host", "0.0.0.0", "--port", "8058"]