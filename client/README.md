# junkslides_client

The junkslides editor in the browser, on the JavaScript target with Lustre: the
cells pane with command and edit modes, the slide pane with canvas mode,
the panes and divider, and the status line.

```sh
just client         # bundle into ../server/priv/static
just client-test    # navigation, keymap, drafts and canvas arithmetic
just e2e            # the editor in headless Chrome against a real server
```
