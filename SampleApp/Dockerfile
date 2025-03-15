FROM python:3.12-slim

WORKDIR /app

# Copy the Python app into the container
COPY sampleapp.py .

# Expose port 80 so it can be accessed externally
EXPOSE 80

# Run the Python app
CMD ["python", "sampleapp.py"]
