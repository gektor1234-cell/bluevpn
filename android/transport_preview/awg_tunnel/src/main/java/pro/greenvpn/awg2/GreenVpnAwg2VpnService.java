package pro.greenvpn.awg2;

import android.content.Intent;
import android.util.AtomicFile;

import androidx.annotation.Nullable;

import org.amnezia.awg.backend.GoBackend;
import org.amnezia.awg.backend.Statistics;
import org.amnezia.awg.backend.Tunnel;
import org.amnezia.awg.config.Config;
import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.Set;

/** Runs the AWG Go runtime outside the application process. */
public final class GreenVpnAwg2VpnService extends GoBackend.VpnService {
    private static final String ACTION_CONNECT = "pro.greenvpn.awg2.action.CONNECT";
    private static final String ACTION_DISCONNECT = "pro.greenvpn.awg2.action.DISCONNECT";
    private static final String EXTRA_OPERATION_ID = "operationId";
    private static final String EXTRA_CONFIG = "config";
    private static final String STATE_FILE = "greenvpn_awg2_state.json";
    private static final String TUNNEL_NAME = "GreenVPN";

    private final Tunnel tunnel = new Tunnel() {
        @Override
        public String getName() {
            return TUNNEL_NAME;
        }

        @Override
        public void onStateChange(final State newState) { }
    };

    @Nullable private GoBackend backend;
    private String lastOperationId = "";

    @Override
    public void onCreate() {
        super.onCreate();
        if (!stateFile().isFile()) writeState("", false, "down", Collections.emptySet(), 0, 0, "");
    }

    @Override
    public int onStartCommand(@Nullable final Intent intent, final int flags, final int startId) {
        final int baseResult = super.onStartCommand(intent, flags, startId);
        if (intent == null || intent.getAction() == null) {
            writeState(lastOperationId, false, "down", Collections.emptySet(), 0, 0, "");
            return baseResult;
        }

        final String requestedOperationId = intent.getStringExtra(EXTRA_OPERATION_ID) == null
                ? ""
                : intent.getStringExtra(EXTRA_OPERATION_ID);
        final String action = intent.getAction();
        final String configText = intent.getStringExtra(EXTRA_CONFIG);
        lastOperationId = requestedOperationId;
        new Thread(() -> {
            try {
                if (ACTION_CONNECT.equals(action)) {
                    connect(requestedOperationId, configText);
                } else if (ACTION_DISCONNECT.equals(action)) {
                    disconnect(requestedOperationId);
                }
            } catch (final Throwable error) {
                writeState(requestedOperationId, false, "error", Collections.emptySet(), 0, 0, rootMessage(error));
            }
        }, "greenvpn-awg2-command").start();
        return baseResult;
    }

    @Override
    public void onDestroy() {
        try {
            super.onDestroy();
        } finally {
            writeState(lastOperationId, false, "down", Collections.emptySet(), 0, 0, "");
        }
    }

    private void connect(final String operationId, @Nullable final String configText) throws Exception {
        if (configText == null || configText.trim().isEmpty()) {
            throw new IllegalArgumentException("AWG2 config is empty");
        }
        writeState(operationId, false, "starting", Collections.emptySet(), 0, 0, "");
        final Config config = Config.parse(
                new ByteArrayInputStream(configText.getBytes(StandardCharsets.UTF_8)));
        final GoBackend currentBackend = backend();
        if (currentBackend.getRunningTunnelNames().contains(TUNNEL_NAME)) {
            currentBackend.setState(tunnel, Tunnel.State.DOWN, null);
        }
        currentBackend.setState(tunnel, Tunnel.State.UP, config);
        writeSnapshot(operationId, currentBackend);
    }

    private void disconnect(final String operationId) throws Exception {
        final GoBackend currentBackend = backend();
        currentBackend.setState(tunnel, Tunnel.State.DOWN, null);
        writeSnapshot(operationId, currentBackend);
    }

    private GoBackend backend() {
        if (backend == null) backend = new GoBackend(getApplicationContext());
        return backend;
    }

    private void writeSnapshot(final String operationId, final GoBackend currentBackend) {
        final Tunnel.State state = currentBackend.getState(tunnel);
        final Set<String> running = currentBackend.getRunningTunnelNames();
        final boolean connected = state == Tunnel.State.UP || running.contains(TUNNEL_NAME);
        long rx = 0;
        long tx = 0;
        if (connected) {
            final Statistics statistics = currentBackend.getStatistics(tunnel);
            rx = statistics.totalRx();
            tx = statistics.totalTx();
        }
        writeState(operationId, connected, state.name().toLowerCase(), running, rx, tx, "");
    }

    private File stateFile() {
        return new File(getNoBackupFilesDir(), STATE_FILE);
    }

    private void writeState(
            final String operationId,
            final boolean connected,
            final String state,
            final Set<String> running,
            final long rx,
            final long tx,
            final String error) {
        final AtomicFile atomicFile = new AtomicFile(stateFile());
        FileOutputStream output = null;
        try {
            final JSONObject json = new JSONObject()
                    .put("operationId", operationId)
                    .put("connected", connected)
                    .put("state", state)
                    .put("runningTunnels", new JSONArray(running))
                    .put("rxBytes", rx)
                    .put("txBytes", tx)
                    .put("error", error)
                    .put("updatedAtMs", System.currentTimeMillis());
            output = atomicFile.startWrite();
            output.write(json.toString().getBytes(StandardCharsets.UTF_8));
            atomicFile.finishWrite(output);
        } catch (final Throwable ignored) {
            if (output != null) atomicFile.failWrite(output);
        }
    }

    private static String rootMessage(final Throwable error) {
        Throwable current = error;
        while (current.getCause() != null && current.getCause() != current) current = current.getCause();
        final String message = current.getMessage();
        return message == null || message.trim().isEmpty()
                ? current.getClass().getSimpleName()
                : message.trim();
    }
}
