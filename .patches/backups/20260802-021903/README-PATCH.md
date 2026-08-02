# workspace-default frontend port 5173

Built against workspace-default commit:
2142330386c32763fa9886ade489515b6295875c

Changes:
- startup.sh defaults FRONTEND_PORT to 5173.
- Vite is explicitly launched on 5173.
- ready.sh checks the frontend on 5173.
- Backend remains on 4000.
