import { createApp } from "./app";
import { loadConfig } from "./config";
import {
  AppAttestSecurity,
  clientIPAddress,
  FileDeviceStore,
} from "./security";

const config = loadConfig();
const devices = await FileDeviceStore.open(config.appAttest.statePath);
const security = new AppAttestSecurity(config.appAttest, devices);
const app = createApp({ config, security });

Bun.serve({
  hostname: "0.0.0.0",
  port: config.port,
  fetch(request, server) {
    const peerAddress = server.requestIP(request)?.address ?? "unknown";
    return app.fetch(
      request,
      clientIPAddress(request, peerAddress, config.clientIPHeader),
    );
  },
});
