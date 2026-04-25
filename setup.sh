#!/bin/bash

# Make scripts executable
chmod +x build.sh
chmod +x examples/run_test.sh
chmod +x examples/test_client.py

echo "Seashell setup complete!"
echo ""
echo "Next steps:"
echo "1. Run './build.sh' to build the project"
echo "2. Add Seashell to your Claude Desktop config (see config/claude-desktop-config.json for a template)"
echo "3. Open Wave Terminal and (optionally) start the Seashell Helper widget"
echo "4. Test with './examples/run_test.sh'"
