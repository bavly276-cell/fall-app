const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

admin.initializeApp();

exports.onSafetyAlertCreated = onDocumentCreated(
  'users/{childDeviceId}/safety_alerts/{alertId}',
  async (event) => {
    const alert = event.data?.data();
    if (!alert) return;

    const parentDeviceId = (alert.parentDeviceId || '').trim();
    if (!parentDeviceId) return;

    const parentDoc = await admin
      .firestore()
      .collection('users')
      .doc(parentDeviceId)
      .get();

    if (!parentDoc.exists) return;

    const parentData = parentDoc.data() || {};
    const token = (parentData.fcmToken || '').trim();
    if (!token) return;

    const hr = Number(alert.heartRate || 0).toFixed(0);
    const spo2 = Number(alert.spo2 || 0).toFixed(1);
    const fall = alert.fallDetected ? 'YES' : 'NO';
    const mapsUrl = String(alert.mapsUrl || '');
    const reason = String(alert.alertReason || 'Safety Alert');

    const message = {
      token,
      notification: {
        title: `Kids Safety Alert: ${reason}`,
        body: `HR ${hr} bpm | SpO2 ${spo2}% | Fall ${fall}`,
      },
      data: {
        childDeviceId: String(alert.childDeviceId || ''),
        alertLevel: String(alert.alertLevel || 'danger'),
        alertReason: reason,
        heartRate: String(alert.heartRate || ''),
        spo2: String(alert.spo2 || ''),
        fallDetected: String(alert.fallDetected || false),
        latitude: String(alert.latitude || ''),
        longitude: String(alert.longitude || ''),
        mapsUrl,
        triggerType: String(alert.triggerType || ''),
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'kids_safety_alerts',
          clickAction: 'FLUTTER_NOTIFICATION_CLICK',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
          },
        },
      },
    };

    await admin.messaging().send(message);
  },
);
