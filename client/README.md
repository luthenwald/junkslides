# zeno_client

The Zeno editor in the browser, on the JavaScript target with Lustre: the
cells pane with command and edit modes, the panes and divider, and the
status line. The slide pane is a placeholder until M4. See
docs/05-editor.md.

```sh
just client         # bundle into ../server/priv/static
just client-test    # navigation, keymap and drafts, on JavaScript
just e2e            # the editor in headless Chrome against a real server
```
