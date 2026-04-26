import 'package:workpalbackend/src/config/env.dart';
import 'package:workpalbackend/src/firebase/firestore_rest_client.dart';

final customerProfileActivityService = CustomerProfileActivityService();

class CustomerProfileActivityService {
  CustomerProfileActivityService({FirestoreRestClient? firestoreClient})
    : _firestoreClient =
          firestoreClient ??
          FirestoreRestClient(
            projectId: AppEnv.firebaseProjectId,
            webApiKey: AppEnv.firebaseWebApiKey,
          );

  final FirestoreRestClient _firestoreClient;

  Future<Map<String, dynamic>> buildCustomerActivity({
    required String idToken,
    required String customerId,
    int maxItems = 20,
    int maxPages = 25,
  }) async {
    final normalizedCustomerId = customerId.trim();
    if (normalizedCustomerId.isEmpty) {
      return _emptyActivity();
    }

    final jobPosts = <Map<String, dynamic>>[];
    final hireHistory = <Map<String, dynamic>>[];
    String? pageToken;
    var loops = 0;

    while (loops < maxPages) {
      final page = await _firestoreClient.listDocumentsPage(
        collectionPath: 'job_posts',
        idToken: idToken,
        pageSize: 100,
        orderBy: 'createdAt desc',
        pageToken: pageToken,
      );

      for (final raw in page.documents) {
        if ('${raw['customerId'] ?? ''}'.trim() != normalizedCustomerId) {
          continue;
        }

        final job = <String, dynamic>{
          ...raw,
          'id': '${raw['id'] ?? raw['jobId'] ?? ''}',
        };
        jobPosts.add(job);

        if ('${job['assignedVendorId'] ?? ''}'.trim().isNotEmpty) {
          hireHistory.add(job);
        }
      }

      loops++;
      pageToken = page.nextPageToken;
      if (pageToken == null || page.documents.isEmpty) break;
    }

    return <String, dynamic>{
      'jobPosts': jobPosts.take(maxItems).toList(),
      'jobs': jobPosts.take(maxItems).toList(),
      'jobsPostedCount': jobPosts.length,
      'hireHistory': hireHistory.take(maxItems).toList(),
      'hiresCount': hireHistory.length,
    };
  }

  Future<Map<String, dynamic>> syncCustomerActivity({
    required String idToken,
    required String customerId,
    Map<String, dynamic>? seedProfile,
  }) async {
    final normalizedCustomerId = customerId.trim();
    if (normalizedCustomerId.isEmpty) return _emptyActivity();

    final activity = await buildCustomerActivity(
      idToken: idToken,
      customerId: normalizedCustomerId,
    );
    final customerProfile = await _firestoreClient.getDocument(
      collectionPath: 'customers',
      documentId: normalizedCustomerId,
      idToken: idToken,
    );
    final usersProfile = await _firestoreClient.getDocument(
      collectionPath: 'users',
      documentId: normalizedCustomerId,
      idToken: idToken,
    );
    final userIdProfile = await _firestoreClient.getDocument(
      collectionPath: 'userId',
      documentId: normalizedCustomerId,
      idToken: idToken,
    );

    final merged = <String, dynamic>{
      if (usersProfile != null) ...usersProfile,
      if (customerProfile != null) ...customerProfile,
      if (userIdProfile != null) ...userIdProfile,
      if (seedProfile != null) ...seedProfile,
      'uid': normalizedCustomerId,
      ...activity,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };

    await _firestoreClient.setDocument(
      collectionPath: 'customers',
      documentId: normalizedCustomerId,
      idToken: idToken,
      data: merged,
    );
    await _firestoreClient.setDocument(
      collectionPath: 'users',
      documentId: normalizedCustomerId,
      idToken: idToken,
      data: merged,
    );
    await _firestoreClient.setDocument(
      collectionPath: 'userId',
      documentId: normalizedCustomerId,
      idToken: idToken,
      data: merged,
    );

    final referralId = '${merged['referralId'] ?? ''}'.trim();
    if (referralId.isNotEmpty) {
      await _firestoreClient.setDocument(
        collectionPath: 'referralId',
        documentId: referralId,
        idToken: idToken,
        data: <String, dynamic>{...merged, 'referralId': referralId},
      );
    }

    return activity;
  }

  Map<String, dynamic> _emptyActivity() {
    return const <String, dynamic>{
      'jobPosts': <Map<String, dynamic>>[],
      'jobs': <Map<String, dynamic>>[],
      'jobsPostedCount': 0,
      'hireHistory': <Map<String, dynamic>>[],
      'hiresCount': 0,
    };
  }
}
