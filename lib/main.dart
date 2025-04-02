import 'dart:async';
import 'dart:convert'; // For jsonDecode/jsonEncode
import 'package:dart_appwrite/dart_appwrite.dart'; // Server-side SDK

/*
  Input: Expected JSON payload in the request body
  {
      "userId": "USER_ID_TO_UPDATE"
  }

  Output:
   - Success: 200 OK with JSON { "success": true, "message": "...", "user": { ...updated user object... } }
   - Error:   400 Bad Request (Missing userId/Invalid JSON), 404 Not Found (User not found), 500 Internal Server Error
*/

Future<void> main(RuntimeRequest req, RuntimeResponse res) async {
  // --- 1. Setup Appwrite Client ---
  // Ensure required environment variables are set in your function settings
  final String? endpoint = req.variables['APPWRITE_ENDPOINT'];
  final String? projectId = req.variables['APPWRITE_PROJECT_ID'];
  final String? apiKey = req.variables['APPWRITE_API_KEY']; // IMPORTANT: Use a Server API Key

  if (endpoint == null || projectId == null || apiKey == null) {
    req.error(
        'Missing required environment variables: APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY');
    return res.json(
      {'success': false, 'message': 'Function misconfiguration.'},
      statusCode: 500,
    );
  }

  final client = Client()
      .setEndpoint(endpoint)
      .setProject(projectId)
      .setKey(apiKey)
      .setSelfSigned(status: true); // Use only on dev instance with self-signed cert

  final users = Users(client);

  // --- 2. Parse Input ---
  Map<String, dynamic> payload;
  try {
    // Handle empty body or potential non-string body
    if (req.bodyRaw == null || req.bodyRaw.isEmpty) {
       req.error('Request body is empty.');
       return res.json(
        {'success': false, 'message': 'Missing request body.'},
        statusCode: 400,
      );
    }
    payload = jsonDecode(req.bodyRaw);
  } catch (e) {
    req.error('Invalid JSON payload: ${e.toString()}');
    return res.json(
      {'success': false, 'message': 'Invalid JSON payload provided.'},
      statusCode: 400,
    );
  }

  final String? userId = payload['userId'] as String?;

  if (userId == null || userId.isEmpty) {
    req.error('Missing userId in request payload.');
    return res.json(
      {'success': false, 'message': 'Missing required field: userId'},
      statusCode: 400,
    );
  }

  req.log("Attempting to add 'admin' label to user: $userId");

  try {
    // --- 3. Get Current User Data ---
    final user = await users.get(userId: userId);

    // --- 4. Prepare New Labels ---
    // Ensure currentLabels is a List<String>, handle null or empty
    final List<String> currentLabels =
        user.labels?.map((label) => label.toString()).toList() ?? [];

    const String adminLabel = 'admin';

    if (currentLabels.contains(adminLabel)) {
      req.log("User $userId already has the '$adminLabel' label.");
      // Optionally return success here if no update is needed
      // return res.json({
      //   'success': true,
      //   'message': 'User already has admin label.',
      //   'user': user.toMap(), // Convert user model to map for JSON
      // }, statusCode: 200);
    }

    // Use a Set to automatically handle duplicates if 'admin' was already there
    final newLabelsSet = Set<String>.from(currentLabels);
    newLabelsSet.add(adminLabel);
    final List<String> newLabels = newLabelsSet.toList();

    // --- 5. Update User Labels ---
    final updatedUser = await users.updateLabels(
      userId: userId,
      labels: newLabels,
    );

    req.log("Successfully added 'admin' label to user $userId.");
    return res.json(
      {
        'success': true,
        'message': 'Admin label added successfully to user $userId.',
        'user': updatedUser.toMap(), // Convert Appwrite model to Map for JSON response
      },
      statusCode: 200,
    );

  } on AppwriteException catch (e) {
    req.error('Appwrite Error for user $userId: [${e.code}] ${e.message}');
    // Handle specific errors like User Not Found
    if (e.code == 404) { // Check Appwrite's specific code for User Not Found
      return res.json(
        {'success': false, 'message': 'User with ID $userId not found.'},
        statusCode: 404,
      );
    }
    // General Appwrite error
    return res.json(
      {
        'success': false,
        'message': 'Failed to add admin label: ${e.message ?? 'Appwrite Error'}'
      },
      statusCode: e.code ?? 500, // Use Appwrite's status code if available
    );
  } catch (e) {
    req.error('Unexpected error for user $userId: ${e.toString()}');
    return res.json(
      {
        'success': false,
        'message': 'Failed to add admin label due to an unexpected error.',
      },
      statusCode: 500, // Use 500 for unexpected server-side errors
    );
  }
}