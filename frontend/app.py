import os

import requests
import streamlit as st

BACKEND_URL = os.environ.get("BACKEND_URL", "http://genai-app.genai-demo.svc.cluster.local:8080")

st.set_page_config(page_title="Self-hosted GenAI Demo", page_icon="🤖")
st.title("Self-hosted GenAI Demo")
st.caption("Backed by Ollama (llama3.2:1b) running in-cluster — no external API, no API key.")

question = st.text_input("Ask something", placeholder="Tell me a one-line joke about Kubernetes")

if st.button("Ask", type="primary") and question:
    with st.spinner("Thinking..."):
        try:
            resp = requests.get(f"{BACKEND_URL}/ask", params={"q": question}, timeout=60)
            resp.raise_for_status()
            data = resp.json()
            st.write(data["answer"])
            st.caption(f"model: {data['model']}")
        except requests.RequestException as e:
            st.error(f"Request failed: {e}")
