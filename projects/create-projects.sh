#!/bin/bash

ORG="MicroTodoSuite"

echo "Creating Scrum project - Development..."
gh project create --title "Scrum - Development Team" --owner "$ORG" --format json < project-template-dev.json

echo "Creating Scrum project - Operations..."
gh project create --title "Scrum - Operations Team" --owner "$ORG" --format json < project-template-ops.json

echo "✅ Projects created. Add views manually from GitHub's UI."