import 'dart:async';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NmmsApp());
}

// -------------------------------------------------------------
// GOOGLE AUTH STATE & HELPERS
// -------------------------------------------------------------
final GoogleSignIn _googleSignIn = GoogleSignIn(
  serverClientId: '310209746661-eebk35c1joor2uamf50j453lsvhskmg8.apps.googleusercontent.com',
  scopes: ['email', 'profile', 'openid'],
);

class AppAuth {
  static GoogleSignInAccount? currentUser;
  static String? userEmail;
  static String? userDisplayName;
  static String? userPhotoUrl;

  static final ValueNotifier<String?> userEmailNotifier = ValueNotifier<String?>(null);

  static bool get isSignedIn => userEmail != null && userEmail!.isNotEmpty;

  static bool get isAdmin {
    if (!isSignedIn) return false;
    final em = userEmail!.toLowerCase();
    return em == 'patelsandip288@gmail.com' || em == 'ponsri.big.gan.nav@gmail.com';
  }

  static Future<void> loadPersistedUser() async {
    final prefs = await SharedPreferences.getInstance();
    userEmail = prefs.getString('auth_user_email');
    userDisplayName = prefs.getString('auth_user_name');
    userPhotoUrl = prefs.getString('auth_user_photo');
    userEmailNotifier.value = userEmail;

    try {
      final account = await _googleSignIn.signInSilently();
      if (account != null) {
        currentUser = account;
        userEmail = account.email;
        userDisplayName = account.displayName ?? userDisplayName;
        userPhotoUrl = account.photoUrl ?? userPhotoUrl;
        userEmailNotifier.value = userEmail;
        await FirestoreService.getFirebaseToken();
      }
    } catch (e) {
      debugPrint('Silent sign in error: $e');
    }
  }

  static Future<bool> signIn(BuildContext context) async {
    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        currentUser = account;
        userEmail = account.email;
        userDisplayName = account.displayName ?? account.email.split('@')[0];
        userPhotoUrl = account.photoUrl;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_user_email', userEmail!);
        await prefs.setString('auth_user_name', userDisplayName!);
        if (userPhotoUrl != null) {
          await prefs.setString('auth_user_photo', userPhotoUrl!);
        }
        await prefs.setString('student_name', userDisplayName!);
        userEmailNotifier.value = userEmail;

        await FirestoreService.getFirebaseToken();
        return true;
      }
    } catch (e) {
      debugPrint('Google Sign-In notice: $e');
    }
    return false;
  }

  static Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    currentUser = null;
    userEmail = null;
    userDisplayName = null;
    userPhotoUrl = null;
    FirestoreService.currentFirebaseUid = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_user_email');
    await prefs.remove('auth_user_name');
    await prefs.remove('auth_user_photo');
    await prefs.remove('student_name');
    await prefs.remove('firebase_auth_token');
    await prefs.remove('firebase_auth_uid');
    await prefs.remove('firebase_auth_expiry');
    userEmailNotifier.value = null;
  }
}

// -------------------------------------------------------------
// MULTI-CLASS CONFIG & STATE (Std 5 CET vs Std 8 NMMS)
// -------------------------------------------------------------
class ClassConfig {
  final String id; // 'std_5' or 'std_8'
  final int std; // 5 or 8
  final String name; // 'ધોરણ ૫ (Std 5)'
  final String shortName; // 'ધોરણ ૫ (CET)'
  final String examName; // 'કોમન પ્રવેશ પરીક્ષા (CET)'
  final String examType; // 'CET'
  final String defaultQuizId; // 'cet_test_49'
  final String defaultQuizTitle;
  final int defaultTotalQuestions; // 40
  final int defaultDurationMinutes; // 60
  final int passingMarks; // 16
  final String description;

  const ClassConfig({
    required this.id,
    required this.std,
    required this.name,
    required this.shortName,
    required this.examName,
    required this.examType,
    required this.defaultQuizId,
    required this.defaultQuizTitle,
    required this.defaultTotalQuestions,
    required this.defaultDurationMinutes,
    required this.passingMarks,
    required this.description,
  });
}

class MultiClassState {
  static const std5 = ClassConfig(
    id: 'std_5',
    std: 5,
    name: 'ધોરણ ૫ (Std 5)',
    shortName: 'ધોરણ ૫ (CET)',
    examName: 'કોમન પ્રવેશ પરીક્ષા (CET)',
    examType: 'CET',
    defaultQuizId: 'cet_test_49',
    defaultQuizTitle: 'કોમન પ્રવેશ પરીક્ષા (CET) SAT મોક કસોટી - TEST 49',
    defaultTotalQuestions: 40,
    defaultDurationMinutes: 60,
    passingMarks: 16,
    description: 'જ્ઞાન સાધના / જ્ઞાન સેતુ કોમન એન્ટ્રન્સ ટેસ્ટ (CET)',
  );

  static const std8 = ClassConfig(
    id: 'std_8',
    std: 8,
    name: 'ધોરણ ૮ (Std 8)',
    shortName: 'ધોરણ ૮ (NMMS)',
    examName: 'નેશનલ મીન્સ કમ મેરીટ સ્કોલરશીપ (NMMS)',
    examType: 'NMMS',
    defaultQuizId: 'paper52',
    defaultQuizTitle: 'NMMS આદર્શ પ્રશ્નપત્ર ક્રમાંક - 52',
    defaultTotalQuestions: 180,
    defaultDurationMinutes: 180,
    passingMarks: 72,
    description: 'માનસિક ક્ષમતા (MAT) અને શૈક્ષણિક યોગ્યતા (SAT) કસોટી',
  );

  static const List<ClassConfig> availableClasses = [std5, std8];

  static final ValueNotifier<ClassConfig> currentClass = ValueNotifier<ClassConfig>(std5);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString('selected_class_id') ?? 'std_5';
    final found = availableClasses.firstWhere((c) => c.id == savedId, orElse: () => std5);
    currentClass.value = found;
    await LiveQuizState.loadForClass(found.id);

    // Sync cloud multi-class config
    FirestoreService.fetchMultiClassConfig().then((cfg) {
      if (cfg != null && cfg.containsKey('classes')) {
        debugPrint('Firestore multi_class config synced');
      }
    });
  }

  static Future<void> switchClass(String classId) async {
    final found = availableClasses.firstWhere((c) => c.id == classId, orElse: () => std5);
    currentClass.value = found;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_class_id', found.id);
    await LiveQuizState.loadForClass(found.id);
  }
}

// -------------------------------------------------------------
// LIVE QUIZ STATE (Admin Controls What is Live)
// -------------------------------------------------------------
class LiveQuizState {
  static final ValueNotifier<bool> isLive = ValueNotifier<bool>(true);
  static final ValueNotifier<String> activeQuizId = ValueNotifier<String>('cet_test_49');
  static final ValueNotifier<String> activeQuizTitle =
      ValueNotifier<String>('કોમન પ્રવેશ પરીક્ષા (CET) SAT મોક કસોટી - TEST 49');
  static final ValueNotifier<int> totalQuestions = ValueNotifier<int>(40);
  static final ValueNotifier<int> durationMinutes = ValueNotifier<int>(60);
  static final ValueNotifier<int> passingMarks = ValueNotifier<int>(16);

  static Future<void> load() async {
    await MultiClassState.load();
  }

  static Future<void> loadForClass(String classId) async {
    final prefs = await SharedPreferences.getInstance();
    final isStd5 = classId == 'std_5';
    final defQuizId = isStd5 ? 'cet_test_49' : 'paper52';
    final defTitle = isStd5
        ? 'કોમન પ્રવેશ પરીક્ષા (CET) SAT મોક કસોટી - TEST 49'
        : 'NMMS આદર્શ પ્રશ્નપત્ર ક્રમાંક - 52';
    final defTotal = isStd5 ? 40 : 180;
    final defDuration = isStd5 ? 60 : 180;
    final defPass = isStd5 ? 16 : 72;

    isLive.value = prefs.getBool('is_quiz_live_$classId') ?? true;
    activeQuizId.value = prefs.getString('active_quiz_id_$classId') ?? defQuizId;
    activeQuizTitle.value = prefs.getString('active_quiz_title_$classId') ?? defTitle;
    totalQuestions.value = prefs.getInt('active_quiz_total_questions_$classId') ?? defTotal;
    durationMinutes.value = prefs.getInt('active_quiz_duration_minutes_$classId') ?? defDuration;
    passingMarks.value = defPass;

    // Sync cloud live quiz status from Firestore before any exam screen
    // reads the active quiz id (otherwise it can fall back to paper52).
    final cfg = await FirestoreService.fetchLiveQuizConfigForClass(classId) ??
        await FirestoreService.fetchLiveQuizConfig();
    if (cfg != null) {
      if (cfg.containsKey('isLive')) isLive.value = cfg['isLive'] as bool;
      if (cfg.containsKey('activeQuizId')) activeQuizId.value = cfg['activeQuizId'] as String;
      if (cfg.containsKey('activeQuizTitle')) activeQuizTitle.value = cfg['activeQuizTitle'] as String;
      if (cfg.containsKey('totalQuestions')) {
        totalQuestions.value = cfg['totalQuestions'] as int? ?? defTotal;
      }
      if (cfg.containsKey('durationMinutes')) {
        durationMinutes.value = cfg['durationMinutes'] as int? ?? defDuration;
      }
      passingMarks.value = ((totalQuestions.value) * 0.4).round();
    }
  }

  static Future<void> setLiveQuiz(String id, String title, {int? total, int? duration, String? classId}) async {
    final targetClass = classId ?? MultiClassState.currentClass.value.id;
    final isStd5 = targetClass == 'std_5';
    final t = total ?? (isStd5 ? 40 : 180);
    final d = duration ?? (isStd5 ? 60 : 180);

    isLive.value = true;
    activeQuizId.value = id;
    activeQuizTitle.value = title;
    totalQuestions.value = t;
    durationMinutes.value = d;
    passingMarks.value = (t * 0.4).round();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_quiz_live_$targetClass', true);
    await prefs.setString('active_quiz_id_$targetClass', id);
    await prefs.setString('active_quiz_title_$targetClass', title);
    await prefs.setInt('active_quiz_total_questions_$targetClass', t);
    await prefs.setInt('active_quiz_duration_minutes_$targetClass', d);

    // Also update legacy keys
    await prefs.setBool('is_quiz_live', true);
    await prefs.setString('active_quiz_id', id);
    await prefs.setString('active_quiz_title', title);
    await prefs.setInt('active_quiz_total_questions', t);
    await prefs.setInt('active_quiz_duration_minutes', d);

    final ids = prefs.getStringList('past_live_quiz_ids') ?? [];
    if (!ids.contains(id)) {
      ids.add(id);
      await prefs.setStringList('past_live_quiz_ids', ids);
    }

    FirestoreService.saveLiveQuizConfigForClass(targetClass, true, id, title, total: t, duration: d);
    FirestoreService.saveLiveQuizConfig(
      true,
      id,
      title,
      totalQuestions: t,
      durationMinutes: d,
      passingMarks: (t * 0.4).round(),
      classId: targetClass,
      std: isStd5 ? 5 : 8,
      examType: isStd5 ? 'CET' : 'NMMS',
    );
  }

  static Future<void> stopLiveQuiz({String? classId}) async {
    final targetClass = classId ?? MultiClassState.currentClass.value.id;
    isLive.value = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_quiz_live_$targetClass', false);
    await prefs.setBool('is_quiz_live', false);
    FirestoreService.saveLiveQuizConfigForClass(targetClass, false, activeQuizId.value, activeQuizTitle.value);
  }
}

// -------------------------------------------------------------
// FIRESTORE CLOUD DATABASE SERVICE (Multi-Quiz, Leaderboard, Submissions)
// -------------------------------------------------------------
class FirestoreService {
  static const String projectId = 'nmms-ponsrischool';
  static const String webApiKey = 'AIzaSyC-e516egy6mQlxyV9jPjl2w82kiNoILcU';
  static const String baseUrl =
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  static Map<String, dynamic> _encodeValue(dynamic value) {
    if (value == null) {
      return {'nullValue': null};
    } else if (value is bool) {
      return {'booleanValue': value};
    } else if (value is int) {
      return {'integerValue': value.toString()};
    } else if (value is double) {
      return {'doubleValue': value};
    } else if (value is String) {
      return {'stringValue': value};
    } else if (value is List) {
      return {
        'arrayValue': {
          'values': value.map((v) => _encodeValue(v)).toList(),
        }
      };
    } else if (value is Map) {
      final fields = <String, dynamic>{};
      value.forEach((k, v) {
        fields[k.toString()] = _encodeValue(v);
      });
      return {'mapValue': {'fields': fields}};
    }
    return {'stringValue': value.toString()};
  }

  static dynamic _decodeValue(Map<String, dynamic> f) {
    if (f.containsKey('stringValue')) return f['stringValue'];
    if (f.containsKey('integerValue')) return int.tryParse(f['integerValue'].toString()) ?? 0;
    if (f.containsKey('doubleValue')) return (f['doubleValue'] as num).toDouble();
    if (f.containsKey('booleanValue')) return f['booleanValue'];
    if (f.containsKey('nullValue')) return null;
    if (f.containsKey('arrayValue')) {
      final values = f['arrayValue']['values'] as List?;
      if (values == null) return [];
      return values.map((v) => _decodeValue(v as Map<String, dynamic>)).toList();
    }
    if (f.containsKey('mapValue')) {
      final fields = f['mapValue']['fields'] as Map<String, dynamic>?;
      if (fields == null) return {};
      final res = <String, dynamic>{};
      fields.forEach((k, v) {
        res[k] = _decodeValue(v as Map<String, dynamic>);
      });
      return res;
    }
    return null;
  }

  static String? currentFirebaseUid;

  static Future<String?> getFirebaseToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('firebase_auth_token');
      final cachedUid = prefs.getString('firebase_auth_uid');
      final expiry = prefs.getInt('firebase_auth_expiry') ?? 0;
      if (cached != null && DateTime.now().millisecondsSinceEpoch < expiry) {
        currentFirebaseUid = cachedUid;
        return cached;
      }

      if (AppAuth.currentUser == null) {
        try {
          AppAuth.currentUser = await _googleSignIn.signInSilently();
        } catch (_) {}
      }

      if (AppAuth.currentUser != null) {
        final auth = await AppAuth.currentUser!.authentication;
        debugPrint('Google Sign-In auth: idToken=${auth.idToken != null}, accessToken=${auth.accessToken != null}');
        if (auth.idToken != null) {
          final res = await http.post(
            Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=$webApiKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'postBody': 'id_token=${auth.idToken}&providerId=google.com',
              'requestUri': 'http://localhost',
              'returnIdpCredential': true,
              'returnSecureToken': true,
            }),
          );
          debugPrint('signInWithIdp statusCode: ${res.statusCode}');
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final token = data['idToken'] as String?;
            final uid = data['localId'] as String?;
            final expiresIn = int.tryParse(data['expiresIn']?.toString() ?? '3600') ?? 3600;
            if (token != null) {
              currentFirebaseUid = uid;
              await prefs.setString('firebase_auth_token', token);
              if (uid != null) {
                await prefs.setString('firebase_auth_uid', uid);
              }
              await prefs.setInt('firebase_auth_expiry', DateTime.now().millisecondsSinceEpoch + (expiresIn - 120) * 1000);
              return token;
            }
          } else {
            debugPrint('signInWithIdp error: ${res.body}');
          }
        }
      }
    } catch (e) {
      debugPrint('Firebase token exchange error: $e');
    }
    return null;
  }

  // 1. Submit Full Exam to Firestore 'submissions' collection
  static Future<bool> saveSubmission({
    required String quizId,
    required String quizTitle,
    required String studentName,
    required String studentRoll,
    required String studentSchool,
    required String email,
    required String? photoURL,
    required int score,
    required int total,
    required int percentage,
    required bool isPassed,
    required int timeTakenSecs,
    required String timeFormatted,
    required Map<String, dynamic> sectionScores,
    required List<Map<String, dynamic>> questionAnalysis,
    required int strikeCount,
    required bool isLiveExam,
  }) async {
    try {
      final token = await getFirebaseToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final payload = {
        'fields': {
          'quizId': _encodeValue(quizId),
          'quizTitle': _encodeValue(quizTitle),
          'studentName': _encodeValue(studentName),
          'studentRoll': _encodeValue(studentRoll),
          'studentSchool': _encodeValue(studentSchool),
          'email': _encodeValue(email),
          'photoURL': _encodeValue(photoURL ?? ''),
          'score': _encodeValue(score),
          'total': _encodeValue(total),
          'percentage': _encodeValue(percentage),
          'isPassed': _encodeValue(isPassed),
          'timeTakenSecs': _encodeValue(timeTakenSecs),
          'timeFormatted': _encodeValue(timeFormatted),
          'submittedAt': _encodeValue(DateTime.now().toIso8601String()),
          'dateFormatted': _encodeValue(LiveLeaderboardManager.formatDateNow()),
          'device': _encodeValue('Android Secure App'),
          'strikeCount': _encodeValue(strikeCount),
          'isLiveExam': _encodeValue(isLiveExam),
          'sectionScores': _encodeValue(sectionScores),
        }
      };

      final url = Uri.parse('$baseUrl/submissions');
      final res = await http.post(url, headers: headers, body: jsonEncode(payload));
      debugPrint('Firestore saveSubmission response: ${res.statusCode}');
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('Firestore saveSubmission error: $e');
      return false;
    }
  }

  // 2. Save / Update Leaderboard in Firestore 'leaderboard' collection
  static Future<bool> saveLeaderboardEntry(LiveLeaderboardEntry entry, {bool alsoSyncLegacy = false}) async {
    try {
      final token = await getFirebaseToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final cleanEmail = entry.email.isNotEmpty
          ? entry.email.replaceAll(RegExp(r'[^\w]'), '_')
          : '${entry.studentName}_${entry.studentRoll}'.replaceAll(RegExp(r'[^\w]'), '_');

      final prefs = await SharedPreferences.getInstance();
      final uid = currentFirebaseUid ?? prefs.getString('firebase_auth_uid') ?? entry.uid;
      // In Firestore, docId must match user's Firebase UID for security rules to allow write
      final docId = (uid.isNotEmpty) ? uid : cleanEmail;

      final payload = {
        'fields': {
          'id': _encodeValue(docId),
          'uid': _encodeValue(docId),
          'quizId': _encodeValue(entry.quizId),
          'quizTitle': _encodeValue(entry.quizTitle),
          'name': _encodeValue(entry.studentName),
          'roll': _encodeValue(entry.studentRoll),
          'school': _encodeValue(entry.studentSchool),
          'email': _encodeValue(entry.email),
          'photoURL': _encodeValue(entry.photoURL),
          'score': _encodeValue(entry.score),
          'total': _encodeValue(entry.total),
          'pct': _encodeValue(entry.pct),
          'isPassed': _encodeValue(entry.isPassed),
          'timeTakenSecs': _encodeValue(entry.timeTakenSecs),
          'timeSeconds': _encodeValue(entry.timeTakenSecs),
          'timeFormatted': _encodeValue(entry.timeFormatted),
          'date': _encodeValue(entry.date),
          'timestamp': _encodeValue(entry.timestamp),
          'sectionScores': _encodeValue(entry.sectionScores),
          'examType': _encodeValue(entry.isLiveExam ? 'LIVE' : 'PRACTICE'),
        }
      };

      final url = Uri.parse('$baseUrl/leaderboard/$docId');
      final res = await http.patch(url, headers: headers, body: jsonEncode(payload));
      debugPrint('Firestore saveLeaderboardEntry ($docId) response: ${res.statusCode}');
      if (res.statusCode != 200 && res.statusCode != 201) {
        debugPrint('Firestore saveLeaderboardEntry error body: ${res.body}');
      }
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('Firestore saveLeaderboardEntry error: $e');
      return false;
    }
  }

  // 3. Fetch Leaderboard from Firestore for a specific quiz (Paper 52, Paper 51, MAT, SAT, etc.)
  static Future<List<LiveLeaderboardEntry>> fetchLeaderboard(String quizId) async {
    try {
      final url = Uri.parse('$baseUrl/leaderboard?pageSize=100');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['documents'] as List?;
        if (docs != null) {
          final List<LiveLeaderboardEntry> list = [];
          for (final doc in docs) {
            final fields = doc['fields'] as Map<String, dynamic>?;
            if (fields == null) continue;

            final itemQuizId = fields['quizId'] != null ? _decodeValue(fields['quizId'])?.toString() : null;

            // Match quizId or fallback legacy docs to paper52
            final matchesQuiz = (itemQuizId == quizId) || (itemQuizId == null && quizId == 'paper52');
            if (!matchesQuiz) continue;

            final name = fields['name'] != null ? _decodeValue(fields['name'])?.toString() ?? '' : '';
            if (name.isEmpty) continue;

            final uid = fields['uid'] != null ? _decodeValue(fields['uid'])?.toString() ?? '' : '';
            final score = fields['score'] != null ? _decodeValue(fields['score']) as int? ?? 0 : 0;
            final total = fields['total'] != null ? _decodeValue(fields['total']) as int? ?? 180 : 180;
            final pct = fields['pct'] != null ? _decodeValue(fields['pct']) as int? ?? 0 : 0;
            final roll = fields['roll'] != null ? _decodeValue(fields['roll'])?.toString() ?? '-' : '-';
            final school = fields['school'] != null ? _decodeValue(fields['school'])?.toString() ?? 'PM SHRI PRATHMIK VIDHYAMANDIR PONSRI' : 'PM SHRI PRATHMIK VIDHYAMANDIR PONSRI';
            final email = fields['email'] != null ? _decodeValue(fields['email'])?.toString() ?? '' : '';
            final photoURL = fields['photoURL'] != null ? _decodeValue(fields['photoURL'])?.toString() ?? '' : '';
            final timeTakenSecs = fields['timeTakenSecs'] != null ? _decodeValue(fields['timeTakenSecs']) as int? ?? 0 : 0;
            final timeFormatted = fields['timeFormatted'] != null ? _decodeValue(fields['timeFormatted'])?.toString() ?? '0:00' : '0:00';
            final date = fields['date'] != null ? _decodeValue(fields['date'])?.toString() ?? '' : '';
            final timestamp = fields['timestamp'] != null ? _decodeValue(fields['timestamp']) as int? ?? 0 : 0;
            final isPassed = fields['isPassed'] != null ? _decodeValue(fields['isPassed']) as bool? ?? false : false;
            final isLiveExam = fields['examType'] != null ? (_decodeValue(fields['examType'])?.toString() == 'LIVE') : true;

            Map<String, dynamic> sectionScores = {};
            if (fields['sectionScores'] != null) {
              final secVal = _decodeValue(fields['sectionScores']);
              if (secVal is Map<String, dynamic>) sectionScores = secVal;
            }

            final newEntry = LiveLeaderboardEntry(
              uid: uid,
              studentName: name,
              studentRoll: roll,
              studentSchool: school,
              email: email,
              photoURL: photoURL,
              score: score,
              total: total,
              pct: pct,
              isPassed: isPassed,
              timeTakenSecs: timeTakenSecs,
              timeFormatted: timeFormatted,
              date: date,
              timestamp: timestamp,
              quizId: quizId,
              quizTitle: LiveLeaderboardManager.getQuizTitle(quizId),
              sectionScores: sectionScores,
              isLiveExam: isLiveExam,
            );

            // Deduplicate by email, uid or name: always keep the latest submission by timestamp!
            final existingIdx = list.indexWhere((e) =>
                (email.isNotEmpty && e.email == email) ||
                (uid.isNotEmpty && e.uid == uid) ||
                (name.isNotEmpty && e.studentName == name && e.studentRoll == roll));
            if (existingIdx == -1) {
              list.add(newEntry);
            } else {
              if (newEntry.timestamp >= list[existingIdx].timestamp) {
                list[existingIdx] = newEntry;
              }
            }
          }

          list.sort((a, b) {
            final c = b.score.compareTo(a.score);
            if (c != 0) return c;
            return a.timeTakenSecs.compareTo(b.timeTakenSecs);
          });

          await LiveLeaderboardManager.saveLocalLeaderboard(quizId, list);
          return list;
        }
      }
    } catch (e) {
      debugPrint('Firestore fetchLeaderboard error: $e');
    }
    return await LiveLeaderboardManager.getLeaderboardForQuiz(quizId);
  }

  // 4. Live Quiz Config in Firestore (Sync Admin Control between Web & APK)
  static Future<Map<String, dynamic>?> fetchMultiClassConfig() async {
    try {
      final token = await getFirebaseToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final url = Uri.parse('$baseUrl/app_config/multi_class?key=$webApiKey');
      final res = await http.get(url, headers: headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final fields = data['fields'] as Map<String, dynamic>?;
        if (fields != null) {
          final decoded = <String, dynamic>{};
          fields.forEach((k, v) {
            decoded[k] = _decodeValue(v as Map<String, dynamic>);
          });
          return decoded;
        }
      }
    } catch (e) {
      debugPrint('Firestore fetchMultiClassConfig error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> fetchLiveQuizConfigForClass(String classId) async {
    try {
      final multi = await fetchMultiClassConfig();
      if (multi != null && multi['classes'] is Map) {
        final classesMap = multi['classes'] as Map;
        if (classesMap.containsKey(classId) && classesMap[classId] is Map) {
          final c = classesMap[classId] as Map;
          final isStd5 = classId == 'std_5';
          return {
            'isLive': c['isLive'] as bool? ?? true,
            'activeQuizId': c['activeQuizId']?.toString() ?? (isStd5 ? 'cet_test_49' : 'paper52'),
            'activeQuizTitle': c['activeQuizTitle']?.toString() ??
                (isStd5
                    ? 'કોમન પ્રવેશ પરીક્ષા (CET) SAT મોક કસોટી - TEST 49'
                    : 'NMMS આદર્શ પ્રશ્નપત્ર ક્રમાંક - 52'),
            'totalQuestions': isStd5 ? 40 : 180,
            'durationMinutes': isStd5 ? 60 : 180,
          };
        }
      }
    } catch (e) {
      debugPrint('Firestore fetchLiveQuizConfigForClass error: $e');
    }
    return await fetchLiveQuizConfig();
  }

  static Future<bool> saveLiveQuizConfigForClass(
    String classId,
    bool isLive,
    String activeQuizId,
    String activeQuizTitle, {
    int total = 180,
    int duration = 180,
  }) async {
    try {
      final token = await getFirebaseToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final multi = await fetchMultiClassConfig() ?? {};
      Map<String, dynamic> classesMap = {};
      if (multi['classes'] is Map) {
        classesMap = Map<String, dynamic>.from(multi['classes'] as Map);
      }

      final isStd5 = classId == 'std_5';
      final existingClassData = (classesMap[classId] is Map)
          ? Map<String, dynamic>.from(classesMap[classId] as Map)
          : <String, dynamic>{};

      existingClassData['isLive'] = isLive;
      existingClassData['activeQuizId'] = activeQuizId;
      existingClassData['activeQuizTitle'] = activeQuizTitle;
      existingClassData['id'] = classId;
      existingClassData['std'] = isStd5 ? 5 : 8;
      existingClassData['examType'] = isStd5 ? 'CET' : 'NMMS';
      existingClassData['examName'] = isStd5 ? 'કોમન પ્રવેશ પરીક્ષા (CET)' : 'નેશનલ મીન્સ કમ મેરીટ સ્કોલરશીપ (NMMS)';
      classesMap[classId] = existingClassData;

      final payload = {
        'fields': {
          'activeClasses': _encodeValue(['std_5', 'std_8']),
          'defaultClass': _encodeValue('std_5'),
          'classes': _encodeValue(classesMap),
          'updatedAt': _encodeValue(DateTime.now().toIso8601String()),
          'updatedBy': _encodeValue(AppAuth.userEmail ?? 'admin'),
        }
      };

      final url = Uri.parse('$baseUrl/app_config/multi_class?key=$webApiKey');
      await http.patch(url, headers: headers, body: jsonEncode(payload));

      // Also update legacy live_quiz config
      await saveLiveQuizConfig(isLive, activeQuizId, activeQuizTitle);
      return true;
    } catch (e) {
      debugPrint('Firestore saveLiveQuizConfigForClass error: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> fetchLiveQuizConfig() async {
    try {
      final url = Uri.parse('$baseUrl/app_config/live_quiz?key=$webApiKey');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final fields = data['fields'] as Map<String, dynamic>?;
        if (fields != null) {
          return {
            'isLive': fields['isLive'] != null ? _decodeValue(fields['isLive']) as bool? ?? true : true,
            'activeQuizId': fields['activeQuizId'] != null ? _decodeValue(fields['activeQuizId'])?.toString() ?? 'paper52' : 'paper52',
            'activeQuizTitle': fields['activeQuizTitle'] != null ? _decodeValue(fields['activeQuizTitle'])?.toString() ?? 'NMMS આદર્શ પ્રશ્નપત્ર ક્રમાંક - 52' : 'NMMS આદર્શ પ્રશ્નપત્ર ક્રમાંક - 52',
            if (fields['totalQuestions'] != null)
              'totalQuestions': _asInt(_decodeValue(fields['totalQuestions'])),
            if (fields['durationMinutes'] != null)
              'durationMinutes': _asInt(_decodeValue(fields['durationMinutes'])),
            if (fields['passingMarks'] != null)
              'passingMarks': _asInt(_decodeValue(fields['passingMarks'])),
            if (fields['classId'] != null)
              'classId': _decodeValue(fields['classId'])?.toString() ?? '',
            if (fields['std'] != null)
              'std': _asInt(_decodeValue(fields['std'])),
            if (fields['examType'] != null)
              'examType': _decodeValue(fields['examType'])?.toString() ?? 'NMMS',
          };
        }
      }
    } catch (e) {
      debugPrint('Firestore fetchLiveQuizConfig error: $e');
    }
    return null;
  }

  static Future<bool> saveLiveQuizConfig(
    bool isLive,
    String activeQuizId,
    String activeQuizTitle, {
    int? totalQuestions,
    int? durationMinutes,
    int? passingMarks,
    String? classId,
    int? std,
    String? examType,
  }) async {
    try {
      final token = await getFirebaseToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final liveFields = <String, dynamic>{
        'isLive': _encodeValue(isLive),
        'activeQuizId': _encodeValue(activeQuizId),
        'activeQuizTitle': _encodeValue(activeQuizTitle),
        'updatedAt': _encodeValue(DateTime.now().toIso8601String()),
        'updatedBy': _encodeValue(AppAuth.userEmail ?? 'admin'),
        if (totalQuestions != null) 'totalQuestions': _encodeValue(totalQuestions),
        if (durationMinutes != null) 'durationMinutes': _encodeValue(durationMinutes),
        if (passingMarks != null) 'passingMarks': _encodeValue(passingMarks),
        if (classId != null) 'classId': _encodeValue(classId),
        if (std != null) 'std': _encodeValue(std),
        if (examType != null) 'examType': _encodeValue(examType),
      };

      final payload = {'fields': liveFields};

      final url = Uri.parse('$baseUrl/app_config/live_quiz?key=$webApiKey');
      final res = await http.patch(url, headers: headers, body: jsonEncode(payload));
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('Firestore saveLiveQuizConfig error: $e');
      return false;
    }
  }

  // 5. Fetch Quiz Questions from Firestore
  static Future<List<dynamic>?> fetchQuizData(String quizId) async {
    try {
      final token = await getFirebaseToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final url = Uri.parse('$baseUrl/quizzes/$quizId');
      final res = await http.get(url, headers: headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final fields = data['fields'] as Map<String, dynamic>?;
        if (fields != null) {
          if (fields['dataJson'] != null) {
            final raw = _decodeValue(fields['dataJson'])?.toString();
            if (raw != null) {
              final parsed = jsonDecode(raw);
              if (parsed is Map && parsed.containsKey('questions')) {
                return parsed['questions'] as List<dynamic>;
              } else if (parsed is List) {
                return parsed;
              }
            }
          }
          // Quizzes imported from the website store their questions as a
          // regular Firestore array field instead of dataJson.
          if (fields['questions'] != null) {
            final decoded = _decodeValue(fields['questions'] as Map<String, dynamic>);
            if (decoded is List && decoded.isNotEmpty) return decoded;
          }
        }
      }
    } catch (e) {
      debugPrint('Firestore fetchQuizData notice: $e');
    }
    return null;
  }

  // 5. Check if student has already attempted this Live Quiz (1 attempt enforcement)
  static Future<bool> checkStudentLiveAttempt(String quizId, String email, {String? studentName, String? studentRoll}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userKey = email.isNotEmpty ? email : '${studentName ?? ''}_${studentRoll ?? ''}';
      if (userKey.isNotEmpty) {
        final localKey = 'live_attempted_${quizId}_$userKey';
        if (prefs.getBool(localKey) == true) {
          return true;
        }
      }

      // Check Firestore leaderboard doc for this quiz and student
      if (email.isNotEmpty) {
        final cleanEmail = email.replaceAll(RegExp(r'[^\w]'), '_');
        final docId = '${quizId}_$cleanEmail';
        final url = Uri.parse('$baseUrl/leaderboard/$docId');
        final res = await http.get(url);
        if (res.statusCode == 200) {
          if (userKey.isNotEmpty) {
            final localKey = 'live_attempted_${quizId}_$userKey';
            await prefs.setBool(localKey, true);
          }
          return true;
        }
      }
    } catch (e) {
      debugPrint('Firestore checkStudentLiveAttempt error: $e');
    }
    return false;
  }
}

// -------------------------------------------------------------
// PERMANENT LIVE LEADERBOARD MANAGER & MULTI-EXAM REPOSITORY
// -------------------------------------------------------------
class LiveLeaderboardEntry {
  final String uid;
  final String studentName;
  final String studentRoll;
  final String studentSchool;
  final String email;
  final String photoURL;
  final int score;
  final int total;
  final int pct;
  final bool isPassed;
  final int timeTakenSecs;
  final String timeFormatted;
  final String date;
  final int timestamp;
  final String quizId;
  final String quizTitle;
  final Map<String, dynamic> sectionScores;
  final bool isLiveExam;

  LiveLeaderboardEntry({
    this.uid = '',
    required this.studentName,
    required this.studentRoll,
    this.studentSchool = 'PM SHRI PRATHMIK VIDHYAMANDIR PONSRI',
    this.email = '',
    this.photoURL = '',
    required this.score,
    required this.total,
    required this.pct,
    this.isPassed = false,
    this.timeTakenSecs = 0,
    this.timeFormatted = '0:00',
    required this.date,
    this.timestamp = 0,
    required this.quizId,
    required this.quizTitle,
    this.sectionScores = const {},
    this.isLiveExam = true,
  });

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'studentName': studentName,
        'studentRoll': studentRoll,
        'studentSchool': studentSchool,
        'email': email,
        'photoURL': photoURL,
        'score': score,
        'total': total,
        'pct': pct,
        'isPassed': isPassed,
        'timeTakenSecs': timeTakenSecs,
        'timeFormatted': timeFormatted,
        'date': date,
        'timestamp': timestamp,
        'quizId': quizId,
        'quizTitle': quizTitle,
        'sectionScores': sectionScores,
        'isLiveExam': isLiveExam,
      };

  factory LiveLeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      LiveLeaderboardEntry(
        uid: json['uid'] ?? '',
        studentName: json['studentName'] ?? json['name'] ?? '',
        studentRoll: json['studentRoll'] ?? json['roll'] ?? '-',
        studentSchool: json['studentSchool'] ?? json['school'] ?? 'PM SHRI PRATHMIK VIDHYAMANDIR PONSRI',
        email: json['email'] ?? '',
        photoURL: json['photoURL'] ?? '',
        score: json['score'] ?? 0,
        total: json['total'] ?? 180,
        pct: json['pct'] ?? 0,
        isPassed: json['isPassed'] ?? ((json['score'] ?? 0) >= 72),
        timeTakenSecs: json['timeTakenSecs'] ?? 0,
        timeFormatted: json['timeFormatted'] ?? '0:00',
        date: json['date'] ?? '',
        timestamp: json['timestamp'] ?? 0,
        quizId: json['quizId'] ?? 'paper52',
        quizTitle: json['quizTitle'] ?? 'NMMS આદર્શ પ્રશ્નપત્ર ક્રમાંક - 52',
        sectionScores: json['sectionScores'] is Map<String, dynamic> ? json['sectionScores'] : {},
        isLiveExam: json['isLiveExam'] ?? true,
      );
}

class LiveLeaderboardManager {
  static String formatDateNow() {
    final now = DateTime.now();
    const months = ['જાન્યુ', 'ફેબ્રુ', 'માર્ચ', 'એપ્રિલ', 'મે', 'જૂન', 'જુલાઈ', 'ઓગસ્ટ', 'સપ્ટે', 'ઓક્ટો', 'નવે', 'ડિસે'];
    return '${now.day} ${months[now.month - 1]}';
  }

  static String getQuizTitle(String quizId) {
    final list = getAllAvailableQuizzes();
    final found = list.firstWhere((q) => q['id'] == quizId, orElse: () => {'title': quizId});
    return found['title'] ?? quizId;
  }

  static Future<List<LiveLeaderboardEntry>> getLeaderboardForQuiz(String quizId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('live_lb_$quizId') ?? [];
    final list = raw.map((s) => LiveLeaderboardEntry.fromJson(jsonDecode(s))).toList();
    list.sort((a, b) {
      final c = b.score.compareTo(a.score);
      if (c != 0) return c;
      return a.timeTakenSecs.compareTo(b.timeTakenSecs);
    });
    return list;
  }

  static Future<void> saveLocalLeaderboard(String quizId, List<LiveLeaderboardEntry> list) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = list.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList('live_lb_$quizId', raw);
  }

  static List<Map<String, String>> getAllAvailableQuizzes({String? classId}) {
    const list = [
      {
        'id': 'cet_test_49',
        'title': 'કોમન પ્રવેશ પરીક્ષા (CET) SAT મોક કસોટી - TEST 49',
        'desc': 'ધોરણ ૫ કોમન પ્રવેશ પરીક્ષા • ગણિત, પર્યાવરણ, ગુજરાતી, અંગ્રેજી, હિન્દી',
        'total': '40',
        'duration': '60',
        'classId': 'std_5',
        'std': '5',
        'examType': 'CET',
        'badge': 'CET ધોરણ ૫',
      },
      {
        'id': 'paper52',
        'title': 'NMMS આદર્શ પ્રશ્નપત્ર ક્રમાંક - 52',
        'desc': 'સંપૂર્ણ મોક ટેસ્ટ • MAT (90) + SAT (90)',
        'total': '180',
        'duration': '180',
        'classId': 'std_8',
        'std': '8',
        'examType': 'NMMS',
        'badge': 'આદર્શ મોક',
      },
      {
        'id': 'paper51',
        'title': 'NMMS પરીક્ષા 2023-24 પ્રશ્નપત્ર - 51',
        'desc': 'પાછલા વર્ષનું વાર્ષિક પેપર • MAT & SAT',
        'total': '180',
        'duration': '180',
        'classId': 'std_8',
        'std': '8',
        'examType': 'NMMS',
        'badge': 'વાર્ષિક પેપર',
      },
      {
        'id': 'paper50',
        'title': 'NMMS પરીક્ષા 2022-23 પ્રશ્નપત્ર - 50',
        'desc': 'પાછલા વર્ષનું વાર્ષિક પેપર • MAT & SAT',
        'total': '180',
        'duration': '180',
        'classId': 'std_8',
        'std': '8',
        'examType': 'NMMS',
        'badge': 'વાર્ષિક પેપર',
      },
      {
        'id': 'mat_special',
        'title': 'NMMS માનસિક ક્ષમતા કસોટી (MAT) સ્પેશિયલ',
        'desc': 'તાર્કિક વિચારણા, શ્રેણી, કોડિંગ-ડીકોડિંગ',
        'total': '90',
        'duration': '90',
        'classId': 'std_8',
        'std': '8',
        'examType': 'NMMS',
        'badge': 'MAT સ્પેશિયલ',
      },
      {
        'id': 'sat_special',
        'title': 'NMMS શૈક્ષણિક યોગ્યતા કસોટી (SAT) સ્પેશિયલ',
        'desc': 'ધોરણ ૭-૮ વિજ્ઞાન, ગણિત, સામાજિક વિજ્ઞાન',
        'total': '90',
        'duration': '90',
        'classId': 'std_8',
        'std': '8',
        'examType': 'NMMS',
        'badge': 'SAT સ્પેશિયલ',
      },
    ];
    if (classId != null && classId.isNotEmpty) {
      return list.where((q) => q['classId'] == classId).toList();
    }
    return list;
  }

  static Future<void> recordLiveSubmission({
    required String quizId,
    required String quizTitle,
    required String studentName,
    required String studentRoll,
    String studentSchool = 'PM SHRI PRATHMIK VIDHYAMANDIR PONSRI',
    String email = '',
    String photoURL = '',
    required int score,
    required int total,
    required int pct,
    bool isPassed = false,
    int timeTakenSecs = 0,
    String timeFormatted = '0:00',
    Map<String, dynamic> sectionScores = const {},
    bool isLiveExam = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final uid = FirestoreService.currentFirebaseUid ?? prefs.getString('firebase_auth_uid') ?? '';

    final entry = LiveLeaderboardEntry(
      uid: uid,
      studentName: studentName,
      studentRoll: studentRoll,
      studentSchool: studentSchool,
      email: email,
      photoURL: photoURL,
      score: score,
      total: total,
      pct: pct,
      isPassed: isPassed,
      timeTakenSecs: timeTakenSecs,
      timeFormatted: timeFormatted,
      date: formatDateNow(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      quizId: quizId,
      quizTitle: quizTitle,
      sectionScores: sectionScores,
      isLiveExam: isLiveExam,
    );

    final currentList = await getLeaderboardForQuiz(quizId);
    final existingIndex = currentList.indexWhere(
      (e) => (email.isNotEmpty && e.email == email) || (uid.isNotEmpty && e.uid == uid) || (e.studentName == studentName && e.studentRoll == studentRoll),
    );
    if (existingIndex >= 0) {
      // Always update to student's latest submission!
      currentList[existingIndex] = entry;
    } else {
      currentList.add(entry);
    }
    await saveLocalLeaderboard(quizId, currentList);

    try {
      await FirestoreService.saveLeaderboardEntry(entry);
    } catch (e) {
      debugPrint('Cloud sync error: $e');
    }
  }
}

// -------------------------------------------------------------
// THEMES DEFINITION (Minimal, Cool, Distraction-Free)
// -------------------------------------------------------------
class AppThemes {
  static final modernIndigo = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: const Color(0xFF4338CA),
    scaffoldBackgroundColor: const Color(0xFFF8FAFC),
    cardColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF4338CA),
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
    ),
  );

  static final simpleLight = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: const Color(0xFF2563EB),
    scaffoldBackgroundColor: const Color(0xFFFFFFFF),
    cardColor: const Color(0xFFF1F5F9),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF2563EB),
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
    ),
  );

  static final oledDark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF090D16),
    colorSchemeSeed: const Color(0xFF6366F1),
    cardColor: const Color(0xFF131B2E),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF131B2E),
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
    ),
  );

  static final forestSage = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: const Color(0xFF0F766E),
    scaffoldBackgroundColor: const Color(0xFFF0FDF4),
    cardColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0F766E),
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
    ),
  );

  static final warmSepia = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: const Color(0xFF9A3412),
    scaffoldBackgroundColor: const Color(0xFFFFFBEB),
    cardColor: const Color(0xFFFEF3C7),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF9A3412),
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
    ),
  );
}

// -------------------------------------------------------------
// AUDIO & SOUND EFFECTS HELPER
// -------------------------------------------------------------
class AppAudio {
  static void playTap() {
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.selectionClick();
  }

  static void playNext() {
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();
  }

  static void playMark() {
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.mediumImpact();
  }

  static void playSubmit() {
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.heavyImpact();
  }

  static void playWarning() {
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();
  }

  static void playCelebration() {
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.mediumImpact();
    Timer(const Duration(milliseconds: 140), () {
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.lightImpact();
    });
  }
}

class NmmsApp extends StatefulWidget {
  const NmmsApp({super.key});

  @override
  State<NmmsApp> createState() => _NmmsAppState();
}

class _NmmsAppState extends State<NmmsApp> {
  int _themeIndex = 0; // 0: Indigo, 1: Simple Light, 2: OLED Dark, 3: Forest, 4: Warm Sepia

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  void _loadPrefs() async {
    await AppAuth.loadPersistedUser();
    await LiveQuizState.load();
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeIndex = prefs.getInt('app_theme_index') ?? 0;
    });
  }

  void _setTheme(int index) async {
    setState(() {
      _themeIndex = index;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('app_theme_index', index);
  }

  void _cycleTheme() {
    _setTheme((_themeIndex + 1) % 5);
  }

  ThemeData _getTheme() {
    switch (_themeIndex) {
      case 1:
        return AppThemes.simpleLight;
      case 2:
        return AppThemes.oledDark;
      case 3:
        return AppThemes.forestSage;
      case 4:
        return AppThemes.warmSepia;
      default:
        return AppThemes.modernIndigo;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _getTheme();
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    // Set notification bar / status bar color to match app theme color
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: primary,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: isDark ? const Color(0xFF090D16) : Colors.white,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return MaterialApp(
      title: 'NMMS Ponsri Exam',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: SplashScreen(
        currentThemeIndex: _themeIndex,
        onThemeChanged: _setTheme,
        onThemeToggle: _cycleTheme,
      ),
    );
  }
}

// -------------------------------------------------------------
// SPLASH SCREEN (Smooth Animated with Pure White Logo)
// -------------------------------------------------------------
class SplashScreen extends StatefulWidget {
  final int currentThemeIndex;
  final ValueChanged<int> onThemeChanged;
  final VoidCallback onThemeToggle;

  const SplashScreen({
    super.key,
    required this.currentThemeIndex,
    required this.onThemeChanged,
    required this.onThemeToggle,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _textFadeAnimation;
  late Animation<Offset> _textSlideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _textSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.35, 0.9, curve: Curves.easeOutCubic),
      ),
    );

    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.35, 0.85, curve: Curves.easeIn),
      ),
    );

    _animController.forward();

    Timer(const Duration(milliseconds: 2200), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 600),
            pageBuilder: (_, __, ___) => MainNavigationShell(
              currentThemeIndex: widget.currentThemeIndex,
              onThemeChanged: widget.onThemeChanged,
              onThemeToggle: widget.onThemeToggle,
            ),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated Pure White Logo Container (No Border Line)
            FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 120,
                  height: 120,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset(
                      'assets/logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          Icon(Icons.school, size: 64, color: primary),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Animated School Title & Platform Subtitle
            SlideTransition(
              position: _textSlideAnimation,
              child: FadeTransition(
                opacity: _textFadeAnimation,
                child: Column(
                  children: [
                    const Text(
                      'પીએમ શ્રી પ્રાથમિક વિદ્યામંદિર પોંસરી',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'NMMS Secure Examination Platform',
                      style: TextStyle(
                        fontSize: 12,
                        color: primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 42),

            FadeTransition(
              opacity: _textFadeAnimation,
              child: const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// MAIN NAVIGATION SHELL WITH BOTTOM TOOLBAR
// -------------------------------------------------------------
class MainNavigationShell extends StatefulWidget {
  final int currentThemeIndex;
  final ValueChanged<int> onThemeChanged;
  final VoidCallback onThemeToggle;

  const MainNavigationShell({
    super.key,
    required this.currentThemeIndex,
    required this.onThemeChanged,
    required this.onThemeToggle,
  });

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: AppAuth.userEmailNotifier,
      builder: (context, userEmail, _) {
        final bool isAdmin = AppAuth.isAdmin;

        final List<Widget> pages = [
          ExamHomeScreen(
            onOpenPastQuizzes: () => setState(() => _selectedIndex = 1),
            onOpenResults: () => setState(() => _selectedIndex = 2),
            onOpenAdmin: isAdmin ? () => setState(() => _selectedIndex = 4) : null,
          ),
          PastQuizzesScreen(
            onSelectQuiz: (quizTitle, quizData, durationMinutes, {quizId}) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExamScreen(
                    studentName: AppAuth.userDisplayName ?? 'વિદ્યાર્થી',
                    studentRoll: '01',
                    customQuizId: quizId,
                    customQuizTitle: quizTitle,
                    customQuizData: quizData,
                    customDurationMinutes: durationMinutes,
                    isLiveExam: false,
                  ),
                ),
              );
            },
          ),
          const PastResultsScreen(),
          ProfileScreen(
            currentThemeIndex: widget.currentThemeIndex,
            onThemeChanged: widget.onThemeChanged,
          ),
          if (isAdmin) const AdminScreen(),
        ];

        final List<NavigationDestination> destinations = [
          const NavigationDestination(
            icon: Icon(Icons.quiz_outlined),
            selectedIcon: Icon(Icons.quiz),
            label: 'કસોટી',
          ),
          const NavigationDestination(
            icon: Icon(Icons.history_edu_outlined),
            selectedIcon: Icon(Icons.history_edu),
            label: 'જૂની કસોટી',
          ),
          const NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events),
            label: 'પરિણામો',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'પ્રોફાઇલ',
          ),
          if (isAdmin)
            const NavigationDestination(
              icon: Icon(Icons.admin_panel_settings_outlined),
              selectedIcon: Icon(Icons.admin_panel_settings),
              label: 'એડમિન',
            ),
        ];

        if (_selectedIndex >= pages.length) {
          _selectedIndex = 0;
        }

        return Scaffold(
          body: pages[_selectedIndex],
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            destinations: destinations,
          ),
        );
      },
    );
  }
}

// -------------------------------------------------------------
// ANIMATED BATTERY WARNING WIDGET (100% Charge Warning)
// -------------------------------------------------------------
class AnimatedBatteryWarningWidget extends StatefulWidget {
  const AnimatedBatteryWarningWidget({super.key});

  @override
  State<AnimatedBatteryWarningWidget> createState() => _AnimatedBatteryWarningWidgetState();
}

class _AnimatedBatteryWarningWidgetState extends State<AnimatedBatteryWarningWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _batteryProgress;
  late Animation<double> _pulseGlow;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _batteryProgress = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
    _pulseGlow = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [
                      const Color(0xFF1E1B4B).withValues(alpha: 0.9),
                      const Color(0xFF064E3B).withValues(alpha: 0.8),
                    ]
                  : [
                      const Color(0xFFFEF3C7),
                      const Color(0xFFDCFCE7),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF10B981).withValues(alpha: 0.5 * _pulseGlow.value),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10B981).withValues(alpha: 0.12 * _pulseGlow.value),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Animated Battery Graphic
                  Container(
                    width: 44,
                    height: 24,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isDark ? Colors.white70 : const Color(0xFF0F172A),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: Row(
                      children: [
                        Expanded(
                          flex: (_batteryProgress.value * 100).toInt(),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _batteryProgress.value > 0.8
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFF59E0B),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: (100 - (_batteryProgress.value * 100)).toInt().clamp(0, 100),
                          child: const SizedBox(),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 3,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white70 : const Color(0xFF0F172A),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(2),
                        bottomRight: Radius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.bolt, color: Color(0xFFF59E0B), size: 22),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'ફોન ૧૦૦% ચાર્જ રાખવો ફરજિયાત છે!',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: isDark ? const Color(0xFF34D399) : const Color(0xFF065F46),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'આ NMMS કસોટી ૧૮૦ મિનિટ (૩ કલાક) ચાલશે. કસોટી દરમિયાન ફોન સ્વીચ-ઑફ ન થાય તે માટે ફોનને ૧૦૦% ચાર્જ રાખીને જ કસોટી શરૂ કરવી અથવા ચાર્જર જોડીને રાખવું.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.battery_charging_full, size: 14, color: Color(0xFF10B981)),
                        const SizedBox(width: 4),
                        Text(
                          '૧૦૦% ચાર્જિંગ સુનિશ્ચિત કરો (100% Charged Required)',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// -------------------------------------------------------------
// TAB 1: EXAM HOME SCREEN (With Instructions & Start)
// -------------------------------------------------------------
class ExamHomeScreen extends StatefulWidget {
  final VoidCallback onOpenPastQuizzes;
  final VoidCallback onOpenResults;
  final VoidCallback? onOpenAdmin;

  const ExamHomeScreen({
    super.key,
    required this.onOpenPastQuizzes,
    required this.onOpenResults,
    this.onOpenAdmin,
  });

  @override
  State<ExamHomeScreen> createState() => _ExamHomeScreenState();
}

class _ExamHomeScreenState extends State<ExamHomeScreen> {
  final _nameController = TextEditingController();
  final _rollController = TextEditingController();
  final _schoolController = TextEditingController(text: 'PM SHRI PRATHMIK VIDHYAMANDIR PONSRI');
  bool _agreedToInstructions = true;
  bool _showInstructionsDetails = true;
  bool _hasAttemptedLiveQuiz = false;

  @override
  void initState() {
    super.initState();
    _loadSavedStudent();
    MultiClassState.currentClass.addListener(_checkLiveAttemptStatus);
    LiveQuizState.activeQuizId.addListener(_checkLiveAttemptStatus);
    LiveQuizState.isLive.addListener(_checkLiveAttemptStatus);
    AppAuth.userEmailNotifier.addListener(_checkLiveAttemptStatus);
  }

  @override
  void dispose() {
    MultiClassState.currentClass.removeListener(_checkLiveAttemptStatus);
    LiveQuizState.activeQuizId.removeListener(_checkLiveAttemptStatus);
    LiveQuizState.isLive.removeListener(_checkLiveAttemptStatus);
    AppAuth.userEmailNotifier.removeListener(_checkLiveAttemptStatus);
    _nameController.dispose();
    _rollController.dispose();
    _schoolController.dispose();
    super.dispose();
  }

  void _loadSavedStudent() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _nameController.text = prefs.getString('student_name') ?? '';
        _rollController.text = prefs.getString('student_roll') ?? '';
      });
      _checkLiveAttemptStatus();
    }
  }

  void _checkLiveAttemptStatus() async {
    final quizId = LiveQuizState.activeQuizId.value;
    final email = AppAuth.userEmail ?? '';
    final name = _nameController.text.trim();
    final roll = _rollController.text.trim();

    final prefs = await SharedPreferences.getInstance();
    final userKey = email.isNotEmpty ? email : '${name}_$roll';
    bool attempted = false;
    if (userKey.isNotEmpty) {
      final localKey = 'live_attempted_${quizId}_$userKey';
      attempted = prefs.getBool(localKey) ?? false;
    }

    if (!attempted && email.isNotEmpty) {
      attempted = await FirestoreService.checkStudentLiveAttempt(quizId, email, studentName: name, studentRoll: roll);
    }

    if (mounted) {
      setState(() {
        _hasAttemptedLiveQuiz = attempted;
      });
    }
  }

  void _saveStudent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('student_name', _nameController.text.trim());
    await prefs.setString('student_roll', _rollController.text.trim());
  }

  void _startTest() {
    if (_hasAttemptedLiveQuiz) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text('કસોટી જમા થઈ ચૂકી છે', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'લાઈવ કસોટીમાં પ્રતિ વિદ્યાર્થી માત્ર ૧ જ પ્રયાસ માન્ય છે.\n\nતમે આ કસોટી સફળતાપૂર્વક પૂર્ણ કરી દીધી છે અને તમારું પરિણામ લીડરબોર્ડમાં નોંધાયેલ છે.\n\nજો તમે ફરીથી મહાવરો / પ્રેક્ટિસ કરવા માંગતા હોવ, તો "જૂની કસોટીઓ" વિભાગમાંથી ગમે તેટલી વાર પ્રેક્ટિસ આપી શકો છો!',
            style: TextStyle(fontSize: 12, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('સમજાઈ ગયું'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                widget.onOpenResults();
              },
              icon: const Icon(Icons.leaderboard, size: 16),
              label: const Text('પરિણામ જુઓ'),
            ),
          ],
        ),
      );
      return;
    }

    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('કૃપા કરીને વિદ્યાર્થીનું પૂરું નામ દાખલ કરો.')),
      );
      return;
    }

    if (!_agreedToInstructions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('કસોટી શરૂ કરવા માટે કૃપા કરીને સૂચનાઓ વાંચી સ્વીકારો.')),
      );
      return;
    }

    _saveStudent();

    // AI Camera Monitoring Security Dialog before starting
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.videocam, color: Colors.red),
            SizedBox(width: 8),
            Text('AI કેમેરા નિરીક્ષણ સૂચના', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'કસોટી દરમિયાન સતત AI કેમેરા મોનિટરિંગ સક્રિય રહેશે.',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red),
            ),
            SizedBox(height: 10),
            Text('• કસોટી આપતી વખતે તમારો ચહેરો સતત કેમેરા સામે હોવો ફરજિયાત છે.', style: TextStyle(fontSize: 12)),
            SizedBox(height: 6),
            Text('• કસોટી શરૂ કરવા માટે કેમેરા પરમિશન આપવી ફરજિયાત છે.', style: TextStyle(fontSize: 12)),
            SizedBox(height: 6),
            Text('• આજુબાજુ જોવું કે અન્ય કોઈ સાથે વાતચીત કરવી સખત પ્રતિબંધિત છે.', style: TextStyle(fontSize: 12)),
            SizedBox(height: 6),
            Text('• એપ ૩ વાર મિનિમાઇઝ કરવાથી કે સ્ક્રીન બંધ કરવાથી પેપર આપમેળે જમા થઈ જશે.', style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('પાછા જાઓ'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              // Request native Android runtime camera permission
              try {
                const channel = MethodChannel('in.ponsrischool.nmms/camera');
                await channel.invokeMethod('requestCameraPermission');
              } catch (e) {
                debugPrint('Native camera request error: $e');
              }
              _proceedToExam();
            },
            icon: const Icon(Icons.videocam, size: 18),
            label: const Text('કેમેરા મંજૂર કરો અને શરૂ કરો'),
          ),
        ],
      ),
    );
  }

  void _proceedToExam() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExamScreen(
          studentName: _nameController.text.trim(),
          studentRoll: _rollController.text.trim(),
          customQuizTitle: LiveQuizState.activeQuizTitle.value,
          isLiveExam: true,
        ),
      ),
    );
    _checkLiveAttemptStatus();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return ValueListenableBuilder<ClassConfig>(
      valueListenable: MultiClassState.currentClass,
      builder: (context, activeClass, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: LiveQuizState.isLive,
          builder: (context, isLive, _) {
            return ValueListenableBuilder<String>(
              valueListenable: LiveQuizState.activeQuizTitle,
              builder: (context, activeTitle, _) {
                return Scaffold(
                  appBar: AppBar(
                    title: Text(
                      '${activeClass.examType} કસોટી પોર્ટલ',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                    actions: [
                      IconButton(
                        tooltip: 'પરિણામો',
                        icon: const Icon(Icons.leaderboard),
                        onPressed: widget.onOpenResults,
                      ),
                    ],
                  ),
                  body: SafeArea(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // School Banner Card
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF131B2E) : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.04),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.asset(
                                      'assets/logo.png',
                                      fit: BoxFit.contain,
                                      errorBuilder: (context, error, stackTrace) =>
                                          Icon(Icons.school, color: primary),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'પીએમ શ્રી પ્રાથમિક વિદ્યામંદિર પોંસરી',
                                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'તા. ગણદેવી, જી. નવસારી • ${activeClass.examType} તૈયારી',
                                        style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isLive
                                              ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                              : Colors.red.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          isLive
                                              ? '● કસોટી સક્રિય છે (LIVE)'
                                              : '● લાઈવ કસોટી બંધ છે (QUIZ STOPPED)',
                                          style: TextStyle(
                                            color: isLive ? const Color(0xFF10B981) : Colors.red,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Multi-Class Switcher Tabs (Std 5 CET vs Std 8 NMMS)
                          Container(
                            margin: const EdgeInsets.only(top: 12),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () => MultiClassState.switchClass('std_5'),
                                    borderRadius: BorderRadius.circular(12),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: activeClass.id == 'std_5' ? primary : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: activeClass.id == 'std_5'
                                            ? [
                                                BoxShadow(
                                                  color: primary.withValues(alpha: 0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.school,
                                            size: 16,
                                            color: activeClass.id == 'std_5'
                                                ? Colors.white
                                                : (isDark ? Colors.white70 : Colors.black87),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'ધોરણ ૫ (CET)',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              color: activeClass.id == 'std_5'
                                                  ? Colors.white
                                                  : (isDark ? Colors.white70 : Colors.black87),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: InkWell(
                                    onTap: () => MultiClassState.switchClass('std_8'),
                                    borderRadius: BorderRadius.circular(12),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: activeClass.id == 'std_8' ? primary : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: activeClass.id == 'std_8'
                                            ? [
                                                BoxShadow(
                                                  color: primary.withValues(alpha: 0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.emoji_events,
                                            size: 16,
                                            color: activeClass.id == 'std_8'
                                                ? Colors.white
                                                : (isDark ? Colors.white70 : Colors.black87),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'ધોરણ ૮ (NMMS)',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              color: activeClass.id == 'std_8'
                                                  ? Colors.white
                                                  : (isDark ? Colors.white70 : Colors.black87),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                      // If NO Quiz is currently live, show clear alert card
                      if (!isLive) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E1B4B) : const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.pause_circle_outline, color: Colors.red, size: 48),
                              const SizedBox(height: 10),
                              const Text(
                                'હાલમાં કોઈ કસોટી લાઈવ નથી',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.red),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'શિક્ષક / એડમિન દ્વારા નવી લાઈવ કસોટી શરૂ કરવામાં આવે ત્યાં સુધી રાહ જુઓ.\nપરંતુ તમે પ્રેક્ટિસ માટે નીચેથી જૂની કસોટીઓ આપી શકો છો!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 14),
                              FilledButton.icon(
                                onPressed: widget.onOpenPastQuizzes,
                                icon: const Icon(Icons.history_edu),
                                label: const Text('જૂની કસોટીઓ આપો (Past Quizzes)'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: primary,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

              const SizedBox(height: 14),

              // Google Sign-In & Profile Status Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF131B2E) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: AppAuth.isSignedIn
                    ? Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: primary.withValues(alpha: 0.15),
                            backgroundImage: AppAuth.userPhotoUrl != null
                                ? NetworkImage(AppAuth.userPhotoUrl!)
                                : null,
                            child: AppAuth.userPhotoUrl == null
                                ? Icon(Icons.person, color: primary, size: 24)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        AppAuth.userDisplayName ?? 'વિદ્યાર્થી',
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.verified, color: Color(0xFF10B981), size: 16),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  AppAuth.userEmail ?? '',
                                  style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              await AppAuth.signOut();
                              setState(() {
                                _nameController.clear();
                              });
                              _checkLiveAttemptStatus();
                            },
                            child: const Text('બદલો', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.account_circle_outlined, color: Colors.redAccent, size: 20),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Google સાઇન-ઇન (Google Account)',
                                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                    ),
                                    Text(
                                      'પરીક્ષા પરિણામ સુરક્ષિત સેવ કરવા લૉગિન કરો',
                                      style: TextStyle(fontSize: 10, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () async {
                              final ok = await AppAuth.signIn(context);
                              if (ok && mounted) {
                                setState(() {
                                  _nameController.text = AppAuth.userDisplayName ?? '';
                                });
                                _checkLiveAttemptStatus();
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF4285F4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.login, size: 18),
                            label: const Text(
                              'Google વડે સાઇન-ઇન કરો',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
              ),

              // Admin Access Banner on Home Screen (ONLY when signed in as Admin)
              if (AppAuth.isAdmin) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF312E81), Color(0xFF4F46E5)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.admin_panel_settings, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'એડમિન મોડ સક્રિય છે 👑',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'કસોટી લાઈવ/સ્ટોપ કરો અને લીડરબોર્ડ નિયંત્રિત કરો',
                              style: TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF4F46E5),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: widget.onOpenAdmin,
                        icon: const Icon(Icons.tune, size: 16),
                        label: const Text('કંટ્રોલ પેનલ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // Student Credentials Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF131B2E) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'વિદ્યાર્થી વિગત (Student Details)',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'પૂરું નામ (Full Name)',
                        prefixIcon: const Icon(Icons.person, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: _rollController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'રોલ નં.',
                              prefixIcon: const Icon(Icons.numbers, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _schoolController,
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: 'શાળા',
                              prefixIcon: const Icon(Icons.account_balance, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Animated Battery 100% Warning Widget
              const AnimatedBatteryWarningWidget(),

              // EXAM INSTRUCTIONS & STRUCTURE CARD (Requested by user)
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF131B2E) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.indigo.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          _showInstructionsDetails = !_showInstructionsDetails;
                        });
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.rule, color: primary, size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'કસોટીનું માળખું અને અગત્યની સૂચનાઓ',
                                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Structure, Duration & Room Instructions',
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              _showInstructionsDetails ? Icons.expand_less : Icons.expand_more,
                              color: primary,
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (_showInstructionsDetails) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Section 1: Structure & Duration
                            _buildInstructionHeader('Structure & Duration', Icons.timer_outlined, Colors.indigo),
                            const SizedBox(height: 6),
                            _buildBulletItem(
                              activeClass.id == 'std_5' ? 'CET Test Structure:' : 'Two Main Tests:',
                              activeClass.id == 'std_5'
                                  ? '• SAT (શૈક્ષણિક યોગ્યતા કસોટી): 40 બહુવિકલ્પ પ્રશ્નો (ગણિત, પર્યાવરણ/વિજ્ઞાન, ગુજરાતી, અંગ્રેજી, હિન્દી) • કુલ સમય 60 મિનિટ.'
                                  : '• MAT (Mental Ability Test): 90 multiple-choice questions testing verbal and non-verbal reasoning, analysis, and critical thinking (90 minutes).\n'
                                      '• SAT (Scholastic Aptitude Test): 90 multiple-choice questions covering Science, Mathematics, and Social Science from Classes 7 and 8 (90 minutes).',
                              isDark,
                            ),
                            const SizedBox(height: 4),
                            _buildBulletItem(
                              'Total Questions & Marks:',
                              activeClass.id == 'std_5'
                                  ? '40 questions / 40 marks (1 mark per question).'
                                  : '180 questions / 180 marks (1 mark per question).',
                              isDark,
                            ),
                            const SizedBox(height: 4),
                            _buildBulletItem(
                              'Passing Criteria:',
                              activeClass.id == 'std_5'
                                  ? 'પાસ થવા માટે ઓછામાં ઓછા 16 ગુણ (40%) જરૂરી છે.'
                                  : 'પાસ થવા માટે ઓછામાં ઓછા 72 ગુણ (40%) જરૂરી છે.',
                              isDark,
                            ),
                            const SizedBox(height: 4),
                            _buildBulletItem(
                              'Negative Marking:',
                              'There is no negative marking.',
                              isDark,
                            ),

                            const SizedBox(height: 14),

                            // Section 2: Common Exam Room Instructions
                            _buildInstructionHeader('Common Exam Room Instructions', Icons.menu_book, Colors.amber.shade800),
                            const SizedBox(height: 6),
                            _buildBulletItem('AI Camera Proctoring:', 'કસોટી દરમિયાન AI કેમેરા નિરીક્ષણ સક્રિય રહેશે. કસોટી આપતી વખતે તમારો ચહેરો સતત કેમેરા સામે રાખવો ફરજિયાત છે.', isDark),
                            _buildBulletItem('OMR Sheet Usage:', 'All answers must be indicated by shading the correct circle on a separate OMR answer sheet using the prescribed pen/pencil.', isDark),
                            _buildBulletItem('Question Booklet Series:', 'You must carefully write and shade your question booklet series code (such as A, B, C, D, or E) on the OMR sheet.', isDark),
                            _buildBulletItem('Rough Work:', 'Use only the blank pages provided at the end of the question booklet for rough work. Do not write on the OMR sheet outside designated fields.', isDark),
                            _buildBulletItem('Time Management:', 'Do not spend too much time on a single question if you are unsure; move on and return to it later if time permits.', isDark),
                            _buildBulletItem('Submission:', 'Hand over the OMR sheet and question booklet (as required by the invigilator) before leaving the exam room.', isDark),

                            const SizedBox(height: 12),

                            // Anti-Cheat Security Notice
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.shield_outlined, color: Colors.orange, size: 20),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'સુરક્ષા ચેતવણી: કસોટી દરમિયાન એપ ૩ વખત મિનિમાઇઝ કરવાથી કે સ્ક્રીન બંધ થવાથી પેપર આપમેળે સબમિટ થઈ જશે.',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 10),

                            // Agreement Checkbox
                            Row(
                              children: [
                                Checkbox(
                                  value: _agreedToInstructions,
                                  onChanged: (val) => setState(() => _agreedToInstructions = val ?? false),
                                ),
                                const Expanded(
                                  child: Text(
                                    'મેં કસોટી સંબંધિત તમામ સૂચનાઓ વાંચી લીધી છે અને હું સહમત છું.',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // LIVE ATTEMPT COMPLETED NOTICE CARD (Strictly 1 attempt per live test)
              if (isLive && _hasAttemptedLiveQuiz) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF064E3B).withValues(alpha: 0.5) : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.6)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.check_circle, color: Color(0xFF10B981), size: 24),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'તમે આ લાઈવ કસોટી પૂર્ણ કરી દીધી છે! ✓',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF047857)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'લાઈવ કસોટીમાં પ્રતિ વિદ્યાર્થી માત્ર ૧ જ પ્રયાસ માન્ય છે જેથી લીડરબોર્ડ પરિણામ વિશ્વસનીય રહે. તમારું પરિણામ લીડરબોર્ડમાં નોંધાઈ ગયું છે.\n\nજો તમે ફરીથી મહાવરો / પ્રેક્ટિસ કરવા માંગતા હોવ, તો "જૂની કસોટીઓ" (Past Quizzes) વિભાગમાંથી ગમે તેટલી વાર પ્રેક્ટિસ આપી શકો છો!',
                        style: TextStyle(fontSize: 11, height: 1.4, color: isDark ? Colors.white70 : const Color(0xFF065F46)),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // START EXAM BUTTON / COMPLETED BUTTON
              if (isLive && _hasAttemptedLiveQuiz)
                FilledButton.icon(
                  onPressed: widget.onOpenResults,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    backgroundColor: const Color(0xFF10B981),
                  ),
                  icon: const Icon(Icons.leaderboard),
                  label: const Text(
                    'કસોટી જમા થયેલ છે (પરિણામ જુઓ)',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: isLive ? _startTest : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    backgroundColor: isLive ? primary : Colors.grey.shade400,
                  ),
                  icon: Icon(isLive ? Icons.play_arrow : Icons.lock_clock),
                  label: Text(
                    isLive
                        ? 'કસોટી શરૂ કરો: $activeTitle'
                        : 'લાઈવ કસોટી હાલમાં બંધ છે',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
        ),
      ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildInstructionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: color),
        ),
      ],
    );
  }

  Widget _buildBulletItem(String title, String description, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            description,
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// TAB 2: PAST QUIZZES ARCHIVE SCREEN
// -------------------------------------------------------------
class PastQuizzesScreen extends StatelessWidget {
  final void Function(String title, List<dynamic>? data, int? durationMinutes, {String? quizId}) onSelectQuiz;

  const PastQuizzesScreen({super.key, required this.onSelectQuiz});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return ValueListenableBuilder<ClassConfig>(
      valueListenable: MultiClassState.currentClass,
      builder: (context, activeClass, _) {
        final List<Map<String, dynamic>> allArchivePapers = activeClass.id == 'std_5'
            ? [
                {
                  'id': 'cet_test_49',
                  'title': 'કોમન પ્રવેશ પરીક્ષા (CET) SAT મોક કસોટી - TEST 49',
                  'subtitle': 'ધોરણ ૫ કોમન પ્રવેશ પરીક્ષા • ગણિત, પર્યાવરણ, ગુજરાતી, અંગ્રેજી, હિન્દી',
                  'questions': 40,
                  'duration': '60 મિનિટ',
                  'badge': 'CET મોક ટેસ્ટ',
                },
              ]
            : [
                {
                  'id': 'paper51',
                  'title': 'NMMS વાર્ષિક પરીક્ષા 2023-24 પ્રશ્નપત્ર - 51',
                  'subtitle': 'પાછલા વર્ષનું વાર્ષિક પેપર • MAT & SAT',
                  'questions': 180,
                  'duration': '180 મિનિટ',
                  'badge': 'વાર્ષિક પેપર',
                },
                {
                  'id': 'paper50',
                  'title': 'NMMS વાર્ષિક પરીક્ષા 2022-23 પ્રશ્નપત્ર - 50',
                  'subtitle': 'પાછલા વર્ષનું વાર્ષિક પેપર • MAT & SAT',
                  'questions': 180,
                  'duration': '180 મિનિટ',
                  'badge': 'વાર્ષિક પેપર',
                },
                {
                  'id': 'mat_special',
                  'title': 'NMMS માનસિક ક્ષમતા કસોટી (MAT) સ્પેશિયલ',
                  'subtitle': 'તાર્કિક વિચારણા, શ્રેણી, કોડિંગ-ડીકોડિંગ',
                  'questions': 90,
                  'duration': '90 મિનિટ',
                  'badge': 'MAT પ્રેક્ટિસ',
                },
                {
                  'id': 'sat_special',
                  'title': 'NMMS શૈક્ષણિક યોગ્યતા કસોટી (SAT) સ્પેશિયલ',
                  'subtitle': 'ધોરણ ૭-૮ વિજ્ઞાન, ગણિત, સામાજિક વિજ્ઞાન',
                  'questions': 90,
                  'duration': '90 મિનિટ',
                  'badge': 'SAT પ્રેક્ટિસ',
                },
                if (LiveQuizState.activeQuizId.value != 'paper52')
                  {
                    'id': 'paper52',
                    'title': 'NMMS આદર્શ પ્રશ્નપત્ર ક્રમાંક - 52',
                    'subtitle': 'સંપૂર્ણ મોક ટેસ્ટ • MAT (90) + SAT (90)',
                    'questions': 180,
                    'duration': '180 મિનિટ',
                    'badge': 'આદર્શ મોક',
                  },
              ];

        return Scaffold(
          appBar: AppBar(
            title: Text('જૂની કસોટીઓ (${activeClass.shortName})'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Class Switcher Filter Tabs
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => MultiClassState.switchClass('std_5'),
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: activeClass.id == 'std_5' ? primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: activeClass.id == 'std_5'
                                ? [
                                    BoxShadow(
                                      color: primary.withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.school,
                                size: 16,
                                color: activeClass.id == 'std_5'
                                    ? Colors.white
                                    : (isDark ? Colors.white70 : Colors.black87),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'ધોરણ ૫ (CET)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: activeClass.id == 'std_5'
                                      ? Colors.white
                                      : (isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: InkWell(
                        onTap: () => MultiClassState.switchClass('std_8'),
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: activeClass.id == 'std_8' ? primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: activeClass.id == 'std_8'
                                ? [
                                    BoxShadow(
                                      color: primary.withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.emoji_events,
                                size: 16,
                                color: activeClass.id == 'std_8'
                                    ? Colors.white
                                    : (isDark ? Colors.white70 : Colors.black87),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'ધોરણ ૮ (NMMS)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: activeClass.id == 'std_8'
                                      ? Colors.white
                                      : (isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Info banner clarifying difference from Live Test
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'સક્રિય લાઈવ કસોટી "${LiveQuizState.activeQuizTitle.value}" હોમ પેજ પર ઉપલબ્ધ છે. નીચેના તમામ પેપર્સ જૂની કસોટીઓ તરીકે પ્રેક્ટિસ માટે છે.',
                        style: TextStyle(fontSize: 11, height: 1.4, color: isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),

              ...allArchivePapers.map((paper) {
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isDark ? Colors.white12 : Colors.black12,
                      width: 1.0,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                paper['badge'] as String,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: primary,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${paper['questions']} પ્રશ્નો • ${paper['duration']}',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          paper['title'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          paper['subtitle'] as String,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            FilledButton.tonal(
                              onPressed: () {
                                final dur = paper['questions'] as int? ?? 180;
                                onSelectQuiz(
                                  paper['title'] as String,
                                  null,
                                  dur,
                                  quizId: paper['id'] as String?,
                                );
                              },
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              ),
                              child: const Text('પ્રેક્ટિસ શરૂ કરો', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

void _showStudentLeaderboardDetail(BuildContext context, LiveLeaderboardEntry entry, int rank) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final primary = Theme.of(context).colorScheme.primary;

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: primary.withValues(alpha: 0.15),
            backgroundImage: entry.photoURL.isNotEmpty ? NetworkImage(entry.photoURL) : null,
            child: entry.photoURL.isEmpty ? Icon(Icons.person, color: primary) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.studentName,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  entry.email.isNotEmpty ? entry.email : 'રોલ નં: ${entry.studentRoll}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '#$rank',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.amber),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF1E1B4B), const Color(0xFF1E293B)]
                      : [const Color(0xFFEEF2FF), const Color(0xFFF1F5F9)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('કુલ ગુણ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Text('${entry.score}/${entry.total}',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: primary)),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('ટકાવારી', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Text('${entry.pct}%',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: primary)),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('સમય', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Text(entry.timeFormatted,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: primary)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.school, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.studentSchool,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.badge_outlined, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text('રોલ નંબર: ${entry.studentRoll}', style: const TextStyle(fontSize: 11)),
                const Spacer(),
                const Icon(Icons.event, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text(entry.date, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
            const Divider(height: 24),
            const Text(
              'વિભાગવાર ગુણ (Section Breakdown):',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (entry.sectionScores.isEmpty)
              const Text('વિભાગવાર વિગત ઉપલબ્ધ નથી.', style: TextStyle(fontSize: 11, color: Colors.grey))
            else
              ...entry.sectionScores.entries.map((e) {
                final sec = e.value is Map ? e.value as Map : {};
                final sName = sec['name']?.toString() ?? e.key;
                final sCorrect = sec['correct'] ?? 0;
                final sTotal = sec['total'] ?? 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(sName, style: const TextStyle(fontSize: 12)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$sCorrect / $sTotal',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primary),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('બંધ કરો'),
        ),
      ],
    ),
  );
}

// -------------------------------------------------------------
// TAB 3: PAST RESULTS & PERMANENT LIVE LEADERBOARDS SCREEN
// -------------------------------------------------------------
class PastResultsScreen extends StatefulWidget {
  const PastResultsScreen({super.key});

  @override
  State<PastResultsScreen> createState() => _PastResultsScreenState();
}

class _PastResultsScreenState extends State<PastResultsScreen> {
  List<Map<String, dynamic>> _myResults = [];
  bool _isLoadingMy = true;

  String _selectedQuizId = 'paper52';
  List<LiveLeaderboardEntry> _liveLeaderboard = [];
  bool _isLoadingLb = false;

  @override
  void initState() {
    super.initState();
    _loadMyResults();
    _loadLiveLeaderboard();
  }

  void _loadMyResults() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('exam_history') ?? [];
    List<Map<String, dynamic>> parsed = [];
    for (var item in raw) {
      try {
        parsed.add(Map<String, dynamic>.from(jsonDecode(item)));
      } catch (_) {}
    }

    // Sync cloud exam attempts from Firestore if signed in (fixes web/mobile history mismatch)
    if (AppAuth.isSignedIn) {
      try {
        final email = AppAuth.userEmail ?? '';
        final cloudEntries = await FirestoreService.fetchLeaderboard(_selectedQuizId);
        for (final entry in cloudEntries) {
          if (entry.email.isNotEmpty && entry.email.toLowerCase() == email.toLowerCase()) {
            final alreadyExists = parsed.any((p) => p['title'] == entry.quizTitle);
            if (!alreadyExists && parsed.isEmpty) {
              parsed.add({
                'score': entry.score,
                'total': entry.total,
                'pct': entry.pct,
                'date': entry.date.isNotEmpty ? entry.date : LiveLeaderboardManager.formatDateNow(),
                'title': entry.quizTitle,
                'isLive': entry.isLiveExam,
                'autoSubmitted': false,
                'sectionScores': entry.sectionScores,
              });
              // Cache in local history so it stays in sync
              final updatedRaw = parsed.map((e) => jsonEncode(e)).toList();
              await prefs.setStringList('exam_history', updatedRaw);
            }
          }
        }
      } catch (e) {
        debugPrint('Cloud myResults sync error: $e');
      }
    }

    if (mounted) {
      setState(() {
        _myResults = parsed.reversed.toList(); // Newest first
        _isLoadingMy = false;
      });
    }
  }

  void _loadLiveLeaderboard() async {
    setState(() {
      _isLoadingLb = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final rawHistory = prefs.getStringList('exam_history') ?? [];

    // If student has a recent exam result in local history, sync it to cloud leaderboard
    if (AppAuth.isSignedIn && rawHistory.isNotEmpty) {
      try {
        final latest = jsonDecode(rawHistory.last) as Map<String, dynamic>;
        final studentScore = latest['score'] is int ? latest['score'] as int : int.tryParse(latest['score']?.toString() ?? '0') ?? 0;
        final studentTotal = latest['total'] is int ? latest['total'] as int : int.tryParse(latest['total']?.toString() ?? '180') ?? 180;
        final studentPct = latest['pct'] is int ? latest['pct'] as int : int.tryParse(latest['pct']?.toString() ?? '0') ?? 0;

        await LiveLeaderboardManager.recordLiveSubmission(
          quizId: _selectedQuizId,
          quizTitle: LiveLeaderboardManager.getQuizTitle(_selectedQuizId),
          studentName: AppAuth.userDisplayName ?? 'વિદ્યાર્થી',
          studentRoll: '01',
          email: AppAuth.userEmail ?? '',
          photoURL: AppAuth.userPhotoUrl ?? '',
          score: studentScore,
          total: studentTotal,
          pct: studentPct,
          isPassed: studentScore >= 72,
          timeTakenSecs: 30,
          timeFormatted: '0:30',
          isLiveExam: true,
        );
      } catch (e) {
        debugPrint('Sync history to leaderboard error: $e');
      }
    }

    final lb = await FirestoreService.fetchLeaderboard(_selectedQuizId);
    if (mounted) {
      setState(() {
        _liveLeaderboard = lb;
        _isLoadingLb = false;
      });
    }
  }

  void _clearMyResults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('exam_history');
    setState(() {
      _myResults = [];
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('તમારો ઇતિહાસ સફળતાપૂર્વક સાફ કરવામાં આવ્યો છે.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final quizzes = LiveLeaderboardManager.getAllAvailableQuizzes();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('પરિણામો અને લીડરબોર્ડ'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.history, size: 20), text: 'મારા પ્રયાસો'),
              Tab(icon: Icon(Icons.emoji_events, size: 20), text: '🏆 લાઈવ લીડરબોર્ડ'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'ઇતિહાસ સાફ કરો',
              onPressed: _clearMyResults,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'રીફ્રેશ કરો',
              onPressed: () {
                _loadMyResults();
                _loadLiveLeaderboard();
              },
            ),
          ],
        ),
        body: TabBarView(
          children: [
            // TAB 1: MY ATTEMPTS
            _isLoadingMy
                ? const Center(child: CircularProgressIndicator())
                : _myResults.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.assignment_outlined, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              const Text(
                                'હજી સુધી કોઈ કસોટી આપવામાં આવી નથી.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'હોમ પેજ પર જઈને NMMS ટેસ્ટ આપો, તમારા પરિણામો અહીં સંગ્રહિત થશે.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _myResults.length,
                        itemBuilder: (context, index) {
                          final res = _myResults[index];
                          final score = res['score'] ?? 0;
                          final total = res['total'] ?? 180;
                          final pct = res['pct'] ?? 0;
                          final date = res['date'] ?? 'આજે';
                          final title = res['title'] ?? 'NMMS આદર્શ પેપર 52';
                          final isPassed = score >= (total * 0.4).round();

                          return Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: (isPassed ? const Color(0xFF10B981) : Colors.red)
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '$score',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 18,
                                          color: isPassed ? const Color(0xFF10B981) : Colors.red,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              isPassed ? 'પાસ (Qualifying) 🏆' : 'સુધારાની જરૂર',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: isPassed ? const Color(0xFF10B981) : Colors.red,
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              '$pct%',
                                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          title,
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$score / $total ગુણ • $date',
                                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                                        ),
                                        if (res['questionAnalysis'] != null &&
                                            (res['questionAnalysis'] as List).isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          FilledButton.tonalIcon(
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => ExamReviewScreen(
                                                    quizTitle: title,
                                                    score: score,
                                                    total: total,
                                                    questionAnalysis:
                                                        res['questionAnalysis'] as List<dynamic>,
                                                  ),
                                                ),
                                              );
                                            },
                                            icon: const Icon(Icons.analytics_outlined, size: 14),
                                            label: const Text('પ્રશ્નો અને સમય વિશ્લેષણ જુઓ',
                                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                            style: FilledButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              minimumSize: Size.zero,
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),

            // TAB 2: PERMANENT LIVE LEADERBOARD
            Column(
              children: [
                // Live Quiz Picker Strip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF131B2E) : const Color(0xFFF1F5F9),
                    border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: quizzes.map((q) {
                        final isSelected = q['id'] == _selectedQuizId;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(q['title']!),
                            selected: isSelected,
                            onSelected: (val) {
                              if (val) {
                                setState(() {
                                  _selectedQuizId = q['id']!;
                                });
                                _loadLiveLeaderboard();
                              }
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                // Leaderboard List
                Expanded(
                  child: _isLoadingLb
                      ? const Center(child: CircularProgressIndicator())
                      : _liveLeaderboard.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.military_tech_outlined, size: 64, color: Colors.amber),
                                    SizedBox(height: 14),
                                    Text(
                                      'આ લાઈવ કસોટી માટે હજી કોઈ પરિણામ નોંધાયેલ નથી.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      'માત્ર લાઈવ કસોટી આપનારા વિદ્યાર્થીઓનું પરિણામ જ કાયમી લીડરબોર્ડમાં સમાવેશ થાય છે.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _liveLeaderboard.length,
                              itemBuilder: (context, index) {
                                final entry = _liveLeaderboard[index];
                                final rank = index + 1;

                                Color rankBadgeColor;
                                String rankMedal = '$rank';
                                if (rank == 1) {
                                  rankBadgeColor = const Color(0xFFF59E0B);
                                  rankMedal = '🥇 1';
                                } else if (rank == 2) {
                                  rankBadgeColor = const Color(0xFF94A3B8);
                                  rankMedal = '🥈 2';
                                } else if (rank == 3) {
                                  rankBadgeColor = const Color(0xFFB45309);
                                  rankMedal = '🥉 3';
                                } else {
                                  rankBadgeColor = isDark ? Colors.white24 : Colors.black26;
                                }

                                return Card(
                                  elevation: 0,
                                  margin: const EdgeInsets.only(bottom: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(
                                      color: rank <= 3
                                          ? rankBadgeColor.withValues(alpha: 0.6)
                                          : (isDark ? Colors.white12 : Colors.black12),
                                      width: rank <= 3 ? 1.5 : 1.0,
                                    ),
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => _showStudentLeaderboardDetail(context, entry, rank),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: rankBadgeColor.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            rankMedal,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: rank <= 3 ? 14 : 16,
                                              color: rankBadgeColor,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                entry.studentName,
                                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'રોલ નં: ${entry.studentRoll} • ${entry.date}',
                                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '${entry.score}/${entry.total}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 15,
                                                color: primary,
                                              ),
                                            ),
                                            Text(
                                              '${entry.pct}%',
                                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                              },
                            ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// TAB 4: PROFILE & THEMES SCREEN
// -------------------------------------------------------------
class ProfileScreen extends StatefulWidget {
  final int currentThemeIndex;
  final ValueChanged<int> onThemeChanged;

  const ProfileScreen({
    super.key,
    required this.currentThemeIndex,
    required this.onThemeChanged,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _name = 'વિદ્યાર્થી';
  String _roll = '-';
  final String _school = 'PM SHRI PRATHMIK VIDHYAMANDIR PONSRI';

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  void _loadDetails() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _name = prefs.getString('student_name') ?? 'વિદ્યાર્થી';
      _roll = prefs.getString('student_roll') ?? '-';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    final themeOptions = [
      {'name': 'Modern Indigo', 'color': const Color(0xFF4338CA)},
      {'name': 'Simple Light', 'color': const Color(0xFF2563EB)},
      {'name': 'OLED Dark', 'color': const Color(0xFF090D16)},
      {'name': 'Forest Sage', 'color': const Color(0xFF0F766E)},
      {'name': 'Warm Sepia', 'color': const Color(0xFF9A3412)},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('પ્રોફાઇલ અને થીમ્સ (Profile)'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Student Profile Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF131B2E) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: primary.withValues(alpha: 0.15),
                      backgroundImage: AppAuth.userPhotoUrl != null
                          ? NetworkImage(AppAuth.userPhotoUrl!)
                          : null,
                      child: AppAuth.userPhotoUrl == null
                          ? Icon(Icons.person, size: 36, color: primary)
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  AppAuth.isSignedIn ? (AppAuth.userDisplayName ?? _name) : _name,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (AppAuth.isSignedIn) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.verified, color: Color(0xFF10B981), size: 18),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppAuth.isSignedIn
                                ? (AppAuth.userEmail ?? '')
                                : 'રોલ નંબર: $_roll',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _school,
                            style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (AppAuth.isSignedIn) ...[
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppAuth.isAdmin
                              ? Colors.purple.withValues(alpha: 0.15)
                              : Colors.blue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          AppAuth.isAdmin ? '👑 એડમિન એકાઉન્ટ' : '🎓 વિદ્યાર્થી એકાઉન્ટ',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppAuth.isAdmin ? Colors.purple : Colors.blue,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await AppAuth.signOut();
                          setState(() {});
                        },
                        icon: const Icon(Icons.logout, size: 14),
                        label: const Text('લૉગઆઉટ', style: TextStyle(fontSize: 11)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Theme Switcher Section
          const Text(
            'એપ થીમ પસંદ કરો (Themes)',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(themeOptions.length, (idx) {
              final opt = themeOptions[idx];
              final isSelected = widget.currentThemeIndex == idx;
              return Expanded(
                child: GestureDetector(
                  onTap: () => widget.onThemeChanged(idx),
                  child: Container(
                    margin: EdgeInsets.only(right: idx == themeOptions.length - 1 ? 0 : 6),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF131B2E) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? primary : (isDark ? Colors.white12 : Colors.black12),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: opt['color'] as Color,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          opt['name'] as String,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),

          const SizedBox(height: 24),

          // Security Status Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF131B2E) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.security, color: Color(0xFF10B981), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'સુરક્ષા ફીચર્સ (Anti-Cheat Active)',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Text('• 3-Strike Minimize Auto-Submit: સક્રિય', style: TextStyle(fontSize: 12)),
                SizedBox(height: 4),
                Text('• Screen Keep Awake: સક્રિય', style: TextStyle(fontSize: 12)),
                SizedBox(height: 4),
                Text('• Firebase Firestore Cloud Sync: સક્રિય', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Privacy Policy Card
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF131B2E) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.shield_outlined, color: primary, size: 22),
              ),
              title: const Text(
                'પ્રાઈવસી પોલિસી (Privacy Policy)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              subtitle: const Text(
                'વિદ્યાર્થી સુરક્ષા, કેમેરા પરમિશન અને ડેટા નિયમો',
                style: TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => _showPrivacyPolicySheet(context, isDark, primary),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'પી.એમ.શ્રી. પ્રાથમિક વિદ્યામંદિર પોંસરી • v1.6.0',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white38 : Colors.black38,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showPrivacyPolicySheet(BuildContext context, bool isDark, Color primary) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.privacy_tip_outlined, color: primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'પ્રાઈવસી પોલિસી (Privacy Policy)',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        Text(
                          'PM SHRI PRATHMIK VIDHYAMANDIR PONSRI',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(height: 24),
              Expanded(
                child: ListView(
                  children: [
                    _buildPolicySection(
                      icon: Icons.person_search_outlined,
                      title: '૧. એકત્રિત માહિતી (Information Collected)',
                      body:
                          'પરીક્ષા પરિણામ અને પ્રમાણીકરણ માટે માત્ર Google એકાઉન્ટ માહિતી (નામ, ઈમેઈલ, પ્રોફાઈલ ફોટો) તથા વિદ્યાર્થીનો રોલ નંબર અને ધોરણ મેળવવામાં આવે છે.',
                      isDark: isDark,
                      primary: primary,
                    ),
                    _buildPolicySection(
                      icon: Icons.camera_alt_outlined,
                      title: '૨. કેમેરા પ્રોક્ટરિંગ (Strictly Local Camera)',
                      body:
                          'પરીક્ષા દરમિયાન પ્રમાણિકતા જળવાય તે માટે ફ્રન્ટ કેમેરા માત્ર ડિવાઇસ સ્ક્રીન પર લોકલ પ્રીવ્યુ તરીકે દેખાય છે. કોઈ પણ ફોટો કે વિડિયો રેકોર્ડ કે સર્વર પર અપલોડ થતો નથી.',
                      isDark: isDark,
                      primary: primary,
                    ),
                    _buildPolicySection(
                      icon: Icons.block_outlined,
                      title: '૩. જાહેરાત મુક્ત (No Advertisements)',
                      body:
                          'આ એપ પ્રાથમિક શાળાના વિદ્યાર્થીઓ (ધોરણ ૫ CET અને ધોરણ ૮ NMMS) માટે સંપૂર્ણ નિઃશુલ્ક અને જાહેરાત મુક્ત છે. કોઈ પણ ડેટા ત્રીજી પાર્ટીને વહેંચવામાં આવતો નથી.',
                      isDark: isDark,
                      primary: primary,
                    ),
                    _buildPolicySection(
                      icon: Icons.cloud_done_outlined,
                      title: '૪. ડેટા સુરક્ષા (Cloud Security)',
                      body:
                          'પરીક્ષા પરિણામો Google Firebase Cloud Firestore પર એન્ક્રિપ્ટેડ સ્વરૂપે સાચવવામાં આવે છે, જે શાળાના અધિકૃત એડમિન સિવાય કોઈ એક્સેસ કરી શકતું નથી.',
                      isDark: isDark,
                      primary: primary,
                    ),
                    _buildPolicySection(
                      icon: Icons.school_outlined,
                      title: '૫. સંપર્ક (School Contact)',
                      body:
                          'પી.એમ.શ્રી. પ્રાથમિક વિદ્યામંદિર પોંસરી, તા. ગણદેવી, જી. નવસારી.\nEmail: patelsandip288@gmail.com / ponsri.big.gan.nav@gmail.com\nવેબસાઇટ: https://nmms.ponsrischool.in/privacy',
                      isDark: isDark,
                      primary: primary,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('સમજાયું (Close)', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPolicySection({
    required IconData icon,
    required String title,
    required String body,
    required bool isDark,
    required Color primary,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white70 : Colors.black87,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// TAB 5: ADMIN CONTROL SCREEN (Google Auth, Live Controller, Leaderboard)
// -------------------------------------------------------------
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  String _selectedAdminQuizId = 'paper52';
  List<LiveLeaderboardEntry> _adminLeaderboard = [];
  bool _isLoadingLb = false;

  @override
  void initState() {
    super.initState();
    _loadAdminLeaderboard();
  }

  void _loadAdminLeaderboard() async {
    setState(() => _isLoadingLb = true);
    final lb = await FirestoreService.fetchLeaderboard(_selectedAdminQuizId);
    if (mounted) {
      setState(() {
        _adminLeaderboard = lb;
        _isLoadingLb = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final allQuizzes = LiveLeaderboardManager.getAllAvailableQuizzes();

    // 1. Google Authentication Gate (No PIN, Only Google Sign-In)
    if (!AppAuth.isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('એડમિન લૉગિન'),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.admin_panel_settings, size: 48, color: Colors.indigo),
                ),
                const SizedBox(height: 20),
                const Text(
                  'શિક્ષક / એડમિન ઓથોરાઇઝેશન',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 8),
                const Text(
                  'કસોટી લાઈવ કરવા, રોકવા અથવા લીડરબોર્ડ નિયંત્રણ માટે એડમિન Google એકાઉન્ટ વડે સાઇન-ઇન કરવું ફરજિયાત છે.\n\n(અધિકૃત: patelsandip288@gmail.com / ponsri.big.gan.nav@gmail.com)',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, height: 1.5, color: Colors.grey),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final ok = await AppAuth.signIn(context);
                    if (ok && mounted) {
                      setState(() {});
                    } else if (mounted) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('આ Google એકાઉન્ટ પાસે એડમિન પરવાનગી નથી.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.login),
                  label: const Text(
                    'Google વડે એડમિન પ્રવેશ કરો',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4285F4),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 2. Admin Control Dashboard (Authorized)
    return ValueListenableBuilder<ClassConfig>(
      valueListenable: MultiClassState.currentClass,
      builder: (context, activeClass, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: LiveQuizState.isLive,
          builder: (context, isLive, _) {
            return ValueListenableBuilder<String>(
              valueListenable: LiveQuizState.activeQuizTitle,
              builder: (context, activeTitle, _) {
                return Scaffold(
                  appBar: AppBar(
                    title: Text('એડમિન પેનલ (${activeClass.shortName}) 👑'),
                    actions: [
                      IconButton(
                        tooltip: 'લૉગઆઉટ',
                        icon: const Icon(Icons.logout),
                        onPressed: () async {
                          await AppAuth.signOut();
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                  body: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Admin Identity Banner
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isDark
                                ? [const Color(0xFF1E1B4B), const Color(0xFF311042)]
                                : [const Color(0xFFEEF2FF), const Color(0xFFFAF5FF)],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.indigo.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: Colors.indigo.withValues(alpha: 0.2),
                              backgroundImage: AppAuth.userPhotoUrl != null
                                  ? NetworkImage(AppAuth.userPhotoUrl!)
                                  : null,
                              child: AppAuth.userPhotoUrl == null
                                  ? const Icon(Icons.shield, color: Colors.indigo, size: 28)
                                  : null,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        AppAuth.userDisplayName ?? 'પટેલ સંદીપ',
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                      ),
                                      const SizedBox(width: 6),
                                      const Icon(Icons.verified, color: Colors.indigo, size: 16),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    AppAuth.userEmail ?? '',
                                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'પીએમ શ્રી શાળા પોંસરી • મુખ્ય એડમિનિસ્ટ્રેટર',
                                    style: TextStyle(fontSize: 10, color: Colors.indigo, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Multi-Class Switcher Tabs for Admin
                      Container(
                        margin: const EdgeInsets.only(top: 14),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => MultiClassState.switchClass('std_5'),
                                borderRadius: BorderRadius.circular(12),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: activeClass.id == 'std_5' ? primary : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: activeClass.id == 'std_5'
                                        ? [
                                            BoxShadow(
                                              color: primary.withValues(alpha: 0.3),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.school,
                                        size: 16,
                                        color: activeClass.id == 'std_5'
                                            ? Colors.white
                                            : (isDark ? Colors.white70 : Colors.black87),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'ધોરણ ૫ (CET)',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: activeClass.id == 'std_5'
                                              ? Colors.white
                                              : (isDark ? Colors.white70 : Colors.black87),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: InkWell(
                                onTap: () => MultiClassState.switchClass('std_8'),
                                borderRadius: BorderRadius.circular(12),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: activeClass.id == 'std_8' ? primary : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: activeClass.id == 'std_8'
                                        ? [
                                            BoxShadow(
                                              color: primary.withValues(alpha: 0.3),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.emoji_events,
                                        size: 16,
                                        color: activeClass.id == 'std_8'
                                            ? Colors.white
                                            : (isDark ? Colors.white70 : Colors.black87),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'ધોરણ ૮ (NMMS)',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: activeClass.id == 'std_8'
                                              ? Colors.white
                                              : (isDark ? Colors.white70 : Colors.black87),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // LIVE QUIZ CONTROLLER CARD
                      Container(
                        padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF131B2E) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isLive ? const Color(0xFF10B981) : Colors.red,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: (isLive ? const Color(0xFF10B981) : Colors.red).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.fiber_manual_record,
                                    size: 10,
                                    color: isLive ? const Color(0xFF10B981) : Colors.red,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isLive ? 'કસોટી લાઈવ ચાલુ છે' : 'કસોટી લાઈવ બંધ છે',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: isLive ? const Color(0xFF10B981) : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            Switch(
                              value: isLive,
                              activeThumbColor: const Color(0xFF10B981),
                              onChanged: (val) async {
                                if (val) {
                                  await LiveQuizState.setLiveQuiz(
                                    LiveQuizState.activeQuizId.value,
                                    LiveQuizState.activeQuizTitle.value,
                                  );
                                } else {
                                  await LiveQuizState.stopLiveQuiz();
                                }
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'સક્રિય લાઈવ કસોટી:',
                          style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          activeTitle,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            if (isLive)
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () async {
                                    await LiveQuizState.stopLiveQuiz();
                                    setState(() {});
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('લાઈવ કસોટી સફળતાપૂર્વક બંધ કરવામાં આવી.')),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.stop, size: 18),
                                  label: const Text('કસોટી લાઈવ બંધ કરો'),
                                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                ),
                              )
                            else
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () async {
                                    await LiveQuizState.setLiveQuiz(
                                      LiveQuizState.activeQuizId.value,
                                      LiveQuizState.activeQuizTitle.value,
                                    );
                                    setState(() {});
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('કસોટી સફળતાપૂર્વક લાઈવ શરૂ કરવામાં આવી.')),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.play_arrow, size: 18),
                                  label: const Text('કસોટી લાઈવ શરૂ કરો'),
                                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  // MAKE ANY PAST QUIZ LIVE SECTION
                  const Text(
                    'કોઈપણ કસોટી લાઈવ બનાવો (Make Any Quiz Live)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'અહીંથી કોઈપણ જૂની કે નવી કસોટી પસંદ કરીને તેને લાઈવ કરી શકો છો:',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),

                  ...allQuizzes.map((quiz) {
                    final isThisLive = isLive && LiveQuizState.activeQuizId.value == quiz['id'];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF131B2E) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isThisLive
                              ? const Color(0xFF10B981)
                              : (isDark ? Colors.white10 : Colors.black12),
                          width: isThisLive ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: (isThisLive ? const Color(0xFF10B981) : primary).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.quiz_outlined,
                              color: isThisLive ? const Color(0xFF10B981) : primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  quiz['title']!,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  quiz['desc']!,
                                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isThisLive)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'સક્રિય લાઈવ',
                                style: TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          else
                            FilledButton.tonal(
                              onPressed: () async {
                                await LiveQuizState.setLiveQuiz(quiz['id']!, quiz['title']!);
                                setState(() {
                                  _selectedAdminQuizId = quiz['id']!;
                                });
                                _loadAdminLeaderboard();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('${quiz['title']} લાઈવ થઈ ગઈ છે!')),
                                  );
                                }
                              },
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('લાઈવ કરો', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 24),

                  // PERMANENT LEADERBOARDS INSPECTOR (ADMIN VIEW)
                  Row(
                    children: [
                      const Icon(Icons.leaderboard, color: Colors.amber, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'કાયમી લાઈવ લીડરબોર્ડ્સ (Permanent Leaderboards)',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: 'રીફ્રેશ',
                        onPressed: _loadAdminLeaderboard,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'માત્ર લાઈવ કસોટી આપનારા વિદ્યાર્થીઓના રેકોર્ડ જ સંગ્રહાય છે:',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 10),

                  // Quiz Filter Chips for Admin Leaderboard
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: allQuizzes.map((q) {
                        final isSelected = q['id'] == _selectedAdminQuizId;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(q['title']!),
                            selected: isSelected,
                            onSelected: (val) {
                              if (val) {
                                setState(() {
                                  _selectedAdminQuizId = q['id']!;
                                });
                                _loadAdminLeaderboard();
                              }
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 12),

                  if (_isLoadingLb)
                    const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                  else if (_adminLeaderboard.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF131B2E) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                      ),
                      child: const Center(
                        child: Text(
                          'આ લાઈવ કસોટી માટે હજી સુધી કોઈ વિદ્યાર્થીએ સબમિટ કર્યું નથી.',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ),
                    )
                  else
                    ...List.generate(_adminLeaderboard.length, (idx) {
                      final item = _adminLeaderboard[idx];
                      final rank = idx + 1;
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: rank <= 3
                                ? (rank == 1 ? Colors.amber : (rank == 2 ? Colors.grey : Colors.brown))
                                : (isDark ? Colors.white12 : Colors.black12),
                            child: Text(
                              rank <= 3 ? (rank == 1 ? '🥇' : (rank == 2 ? '🥈' : '🥉')) : '$rank',
                              style: TextStyle(
                                fontSize: rank <= 3 ? 14 : 12,
                                fontWeight: FontWeight.bold,
                                color: rank <= 3 ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                              ),
                            ),
                          ),
                          title: Text(item.studentName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Text('રોલ નં: ${item.studentRoll} • ${item.date}', style: const TextStyle(fontSize: 10)),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${item.score}/${item.total}', style: TextStyle(fontWeight: FontWeight.bold, color: primary, fontSize: 14)),
                              Text('${item.pct}%', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                          onTap: () => _showStudentLeaderboardDetail(context, item, rank),
                        ),
                      );
                    }),
                ],
              ),
            );
          },
        );
      },
    );
  },
);
  }
}

// -------------------------------------------------------------
// QUESTION DIAGRAM WIDGET (SVG, Image, Zoom & Vector Support)
// -------------------------------------------------------------
class QuestionDiagramView extends StatelessWidget {
  final Map<String, dynamic> question;
  final bool isReview;

  const QuestionDiagramView({
    super.key,
    required this.question,
    this.isReview = false,
  });

  void _showZoomDialog(BuildContext context, Widget child) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.zoom_in, size: 20, color: Colors.blue),
                    const SizedBox(width: 8),
                    const Text(
                      'આકૃતિ ઝૂમ (Pinch to Zoom)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                      tooltip: 'બંધ કરો',
                    ),
                  ],
                ),
                const Divider(),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.65,
                    maxWidth: MediaQuery.of(context).size.width * 0.9,
                  ),
                  child: InteractiveViewer(
                    panEnabled: true,
                    minScale: 0.8,
                    maxScale: 4.0,
                    child: Center(child: child),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasDiagram = question['hasDiagram'] == true;
    final svgString = question['diagramSvg'] as String?;
    final imageUrl = question['image'] as String? ?? question['imageUrl'] as String?;

    if (!hasDiagram &&
        (svgString == null || svgString.trim().isEmpty) &&
        (imageUrl == null || imageUrl.trim().isEmpty)) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget diagramContent;
    if (svgString != null && svgString.trim().isNotEmpty) {
      diagramContent = SvgPicture.string(
        svgString,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    } else if (imageUrl != null && imageUrl.trim().isNotEmpty) {
      if (imageUrl.startsWith('data:image')) {
        try {
          final base64Str = imageUrl.split(',').last;
          diagramContent = Image.memory(
            base64Decode(base64Str),
            fit: BoxFit.contain,
          );
        } catch (_) {
          diagramContent = const Text('ઇમેજ લોડ થઈ શકી નથી');
        }
      } else if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
        diagramContent = Image.network(
          imageUrl,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          },
          errorBuilder: (_, __, ___) => const Center(
            child: Text('ઇમેજ લોડ થઈ શકી નથી', style: TextStyle(color: Colors.red)),
          ),
        );
      } else {
        diagramContent = Image.asset(
          imageUrl,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Center(
            child: Text('આકૃતિ ઉપલબ્ધ નથી'),
          ),
        );
      }
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white24 : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFEEF2F6),
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_mosaic_outlined,
                  size: 14,
                  color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                ),
                const SizedBox(width: 6),
                Text(
                  'પ્રશ્ન આકૃતિ (Diagram)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => _showZoomDialog(context, diagramContent),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.fullscreen,
                          size: 15,
                          color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          'મોટી કરો',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => _showZoomDialog(context, diagramContent),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: Center(child: diagramContent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// SECURE EXAM SCREEN (Anti-Cheat 3-Strike, Timer, Questions)
// -------------------------------------------------------------
class ExamScreen extends StatefulWidget {
  final String studentName;
  final String studentRoll;
  final String? customQuizId;
  final String? customQuizTitle;
  final List<dynamic>? customQuizData;
  final int? customDurationMinutes;
  final bool isLiveExam;

  const ExamScreen({
    super.key,
    required this.studentName,
    required this.studentRoll,
    this.customQuizId,
    this.customQuizTitle,
    this.customQuizData,
    this.customDurationMinutes,
    this.isLiveExam = true,
  });

  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> with WidgetsBindingObserver {
  List<dynamic> _questions = [];
  bool _isLoading = true;
  int _currentIndex = 0;
  final Map<int, int> _answers = {};
  final Set<int> _bookmarks = {};

  int _strikeCount = 0;
  static const int _maxStrikes = 3;
  DateTime? _lastStrikeTime;

  Timer? _examTimer;
  int _initialTotalSeconds = 180 * 60;
  int _remainingSeconds = 180 * 60;

  CameraController? _cameraController;
  bool _isCameraReady = false;
  bool _isCameraCollapsed = false;

  final Map<int, int> _timeSpentPerQuestion = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Secure Fullscreen Exam Mode: hide navigation bar & system bars
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initCamera();
    _loadQuestions();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        final frontCam = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        );
        final ctrl = CameraController(
          frontCam,
          ResolutionPreset.low,
          enableAudio: false,
        );
        _cameraController = ctrl;
        await ctrl.initialize();
        if (mounted) {
          setState(() {
            _isCameraReady = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Camera proctoring init notice: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _examTimer?.cancel();
    _cameraController?.dispose();
    // Restore normal system bars on exit
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      final now = DateTime.now();
      // Debounce multiple lifecycle events from a single minimize to home screen
      if (_lastStrikeTime != null && now.difference(_lastStrikeTime!) < const Duration(seconds: 3)) {
        return;
      }
      _lastStrikeTime = now;
      _strikeCount++;
      if (mounted) {
        if (_strikeCount >= _maxStrikes) {
          AppAudio.playWarning();
          _autoSubmitDueToAntiCheat();
        } else {
          AppAudio.playWarning();
          _showAntiCheatWarningDialog();
        }
      }
    }
  }

  void _showAntiCheatWarningDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            const SizedBox(width: 8),
            Text('ચેતવણી ($_strikeCount/$_maxStrikes)'),
          ],
        ),
        content: const Text(
          'તમે કસોટી દરમિયાન એપ બહાર નીકળ્યા અથવા મિનિમાઇઝ કર્યું.\n\nજો તમે ૩ વખત બહાર નીકળશો તો તમારું પેપર આપમેળે જમા (Auto-Submit) થઈ જશે.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('હું સમજી ગયો/ગઈ (ચાલુ રાખો)'),
          ),
        ],
      ),
    );
  }

  void _autoSubmitDueToAntiCheat() {
    _examTimer?.cancel();
    _submitExam(autoSubmitted: true);
  }

  void _startTimer() {
    _examTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
          _timeSpentPerQuestion[_currentIndex] =
              (_timeSpentPerQuestion[_currentIndex] ?? 0) + 1;
        });
      } else {
        timer.cancel();
        _submitExam(autoSubmitted: false);
      }
    });
  }

  String _formatTimer(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final mins = (totalSeconds % 3600) ~/ 60;
    final secs = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _loadQuestions() async {
    try {
      int durationMins = widget.customDurationMinutes ?? 180;
      if (widget.customDurationMinutes == null && widget.isLiveExam) {
        final configuredDuration = LiveQuizState.durationMinutes.value;
        if (configuredDuration > 0) durationMins = configuredDuration;
      }
      List<dynamic> loadedQuestions = [];

      if (widget.customQuizData != null && widget.customQuizData!.isNotEmpty) {
        loadedQuestions = widget.customQuizData!;
      } else {
        // 1. Try to load live quiz from Firestore first!
        final activeId = widget.isLiveExam
            ? LiveQuizState.activeQuizId.value
            : (widget.customQuizId ?? 'paper52');
        final remoteQuestions = await FirestoreService.fetchQuizData(activeId);
        if (remoteQuestions != null && remoteQuestions.isNotEmpty) {
          loadedQuestions = remoteQuestions;
        } else {
          // 2. Fallback to local asset
          final assetPath = activeId.contains('cet') ? 'assets/cet_test_49.json' : 'assets/paper52.json';
          final jsonString = await rootBundle.loadString(assetPath);
          final data = jsonDecode(jsonString);
          if (data is Map) {
            if (data.containsKey('durationMinutes')) {
              durationMins = data['durationMinutes'] is int
                  ? data['durationMinutes'] as int
                  : (int.tryParse(data['durationMinutes'].toString()) ?? 180);
            } else if (data.containsKey('quiz_info') &&
                data['quiz_info'] is Map &&
                data['quiz_info'].containsKey('duration_minutes')) {
              durationMins = data['quiz_info']['duration_minutes'] is int
                  ? data['quiz_info']['duration_minutes'] as int
                  : (int.tryParse(data['quiz_info']['duration_minutes'].toString()) ?? 180);
            }
            if (data.containsKey('questions')) {
              loadedQuestions = data['questions'] as List<dynamic>;
            }
          } else if (data is List) {
            loadedQuestions = data;
          }
        }
      }

      // If duration not explicitly provided, calculate 1 minute per question automatically!
      if (widget.customDurationMinutes == null && loadedQuestions.isNotEmpty) {
        if (durationMins == 180 && loadedQuestions.length != 180) {
          durationMins = loadedQuestions.length;
        }
      }

      setState(() {
        _questions = loadedQuestions;
        _initialTotalSeconds = durationMins * 60;
        _remainingSeconds = durationMins * 60;
        _isLoading = false;
      });
      _startTimer();
    } catch (_) {
      final int durationMins = widget.customDurationMinutes ?? 180;
      List<dynamic> generated = [];
      for (int i = 1; i <= 180; i++) {
        generated.add({
          'id': i,
          'question': 'પ્રશ્ન $i: NMMS પરીક્ષા પ્રશ્ન',
          'options': ['વિકલ્પ A', 'વિકલ્પ B', 'વિકલ્પ C', 'વિકલ્પ D'],
          'answer': 0,
        });
      }
      setState(() {
        _questions = generated;
        _initialTotalSeconds = durationMins * 60;
        _remainingSeconds = durationMins * 60;
        _isLoading = false;
      });
      _startTimer();
    }
  }

  void _confirmSubmit() {
    final answeredCount = _answers.length;
    final totalCount = _questions.length;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('કસોટી જમા કરવી છે?'),
        content: Text('તમે $totalCount માંથી $answeredCount પ્રશ્નોના ઉત્તર આપ્યા છે.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('પાછા જાઓ')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              AppAudio.playSubmit();
              _submitExam(autoSubmitted: false);
            },
            child: const Text('હા, જમા કરો'),
          ),
        ],
      ),
    );
  }

  void _openQuestionNavigator() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _QuestionNavigatorSheet(
        totalQuestions: _questions.length,
        currentIndex: _currentIndex,
        answers: _answers,
        bookmarks: _bookmarks,
        onSelectQuestion: (index) {
          setState(() {
            _currentIndex = index;
          });
          AppAudio.playTap();
        },
        onSubmit: () {
          _confirmSubmit();
        },
      ),
    );
  }

  void _submitExam({required bool autoSubmitted}) async {
    _examTimer?.cancel();

    int score = 0;
    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      final correct = (q['answer'] ?? q['correct_index'] ?? 0) as int;
      if (_answers[i] == correct) {
        score++;
      }
    }

    final total = _questions.length;
    final pct = total > 0 ? ((score / total) * 100).round() : 0;

    // Build question analysis (which questions were wrong, empty, correct, and time spent)
    final List<Map<String, dynamic>> questionAnalysis = [];
    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      final studentAns = _answers[i];
      final correctAns = (q['answer'] ?? q['correct_index'] ?? 0) as int;
      final timeSpent = _timeSpentPerQuestion[i] ?? 0;
      final bool isGrace = q['isGrace'] == true ||
          q['grace_mark'] == true ||
          q['status'] == 'question_error' ||
          q['status'] == 'no_correct_option';
      final String status = isGrace
          ? 'grace'
          : (studentAns == null
              ? 'unattempted'
              : (studentAns == correctAns ? 'correct' : 'incorrect'));

      questionAnalysis.add({
        'index': i,
        'question': q['question'] ?? 'પ્રશ્ન ${i + 1}',
        'options': q['options'] ?? ['વિકલ્પ A', 'વિકલ્પ B', 'વિકલ્પ C', 'વિકલ્પ D'],
        'studentAnswer': studentAns,
        'correctAnswer': correctAns,
        'status': status,
        'isGrace': isGrace,
        'timeSpentSeconds': timeSpent,
        'hasDiagram': q['hasDiagram'] == true,
        'diagramSvg': q['diagramSvg'],
        'image': q['image'] ?? q['imageUrl'],
        'explanation': q['explanation'],
      });
    }

    final timeTakenSecs = _initialTotalSeconds - _remainingSeconds;
    final takenMins = timeTakenSecs ~/ 60;
    final takenSecs = timeTakenSecs % 60;
    final timeFormatted = '$takenMins:${takenSecs.toString().padLeft(2, '0')}';

    int matScore = 0;
    int satMathsScore = 0;
    int satScienceScore = 0;
    int satSocialScore = 0;

    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      final correct = (q['answer'] ?? q['correct_index'] ?? 0) as int;
      final bool isGrace = q['isGrace'] == true ||
          q['grace_mark'] == true ||
          q['status'] == 'question_error' ||
          q['status'] == 'no_correct_option';
      final isCorrect = isGrace || (_answers[i] == correct);
      if (isCorrect) {
        if (i < 90) {
          matScore++;
        } else if (i < 120) {
          satMathsScore++;
        } else if (i < 150) {
          satScienceScore++;
        } else {
          satSocialScore++;
        }
      }
    }

    final sectionScores = {
      'MAT': {
        'name': '🧠 MAT (માનસિક ક્ષમતા)',
        'correct': matScore,
        'total': total >= 90 ? 90 : total,
      },
      'SAT-Maths': {
        'name': '📐 SAT (ગણિત)',
        'correct': satMathsScore,
        'total': total >= 120 ? 30 : (total > 90 ? total - 90 : 0),
      },
      'SAT-Science': {
        'name': '🔬 SAT (વિજ્ઞાન)',
        'correct': satScienceScore,
        'total': total >= 150 ? 30 : (total > 120 ? total - 120 : 0),
      },
      'SAT-SocialScience': {
        'name': '🌍 SAT (સામાજિક વિજ્ઞાન)',
        'correct': satSocialScore,
        'total': total >= 180 ? 30 : (total > 150 ? total - 150 : 0),
      },
    };

    final isPassed = score >= ((total * 0.40).round());
    final quizId = widget.isLiveExam ? LiveQuizState.activeQuizId.value : (widget.customQuizId ?? 'past_practice');
    final quizTitle = widget.customQuizTitle ?? LiveQuizState.activeQuizTitle.value;

    // Send complete exam submission to Firestore Cloud Database 'submissions' collection
    FirestoreService.saveSubmission(
      quizId: quizId,
      quizTitle: quizTitle,
      studentName: widget.studentName,
      studentRoll: widget.studentRoll,
      studentSchool: 'PM SHRI PRATHMIK VIDHYAMANDIR PONSRI',
      email: AppAuth.userEmail ?? '',
      photoURL: AppAuth.userPhotoUrl,
      score: score,
      total: total,
      percentage: pct,
      isPassed: isPassed,
      timeTakenSecs: timeTakenSecs,
      timeFormatted: timeFormatted,
      sectionScores: sectionScores,
      questionAnalysis: questionAnalysis,
      strikeCount: _strikeCount,
      isLiveExam: widget.isLiveExam,
    );

    // Record to permanent live leaderboard ONLY if this is an official Live Exam
    if (widget.isLiveExam) {
      await LiveLeaderboardManager.recordLiveSubmission(
        quizId: quizId,
        quizTitle: quizTitle,
        studentName: widget.studentName,
        studentRoll: widget.studentRoll,
        studentSchool: 'PM SHRI PRATHMIK VIDHYAMANDIR PONSRI',
        email: AppAuth.userEmail ?? '',
        photoURL: AppAuth.userPhotoUrl ?? '',
        score: score,
        total: total,
        pct: pct,
        isPassed: isPassed,
        timeTakenSecs: timeTakenSecs,
        timeFormatted: timeFormatted,
        sectionScores: sectionScores,
        isLiveExam: true,
      );

      // Lock live quiz to strictly 1 attempt for this student
      final userKey = (AppAuth.userEmail?.isNotEmpty ?? false)
          ? AppAuth.userEmail!
          : '${widget.studentName}_${widget.studentRoll}';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('live_attempted_${quizId}_$userKey', true);
    }

    // Save locally to SharedPreferences for personal history
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('exam_history') ?? [];
    final now = DateTime.now();
    final entry = jsonEncode({
      'score': score,
      'total': total,
      'pct': pct,
      'autoSubmitted': autoSubmitted,
      'isLive': widget.isLiveExam,
      'date': '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
      'title': widget.customQuizTitle ?? LiveQuizState.activeQuizTitle.value,
      'questionAnalysis': questionAnalysis,
    });
    history.add(entry);
    await prefs.setStringList('exam_history', history);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            score: score,
            total: total,
            pct: pct,
            autoSubmitted: autoSubmitted,
            studentName: widget.studentName,
            quizTitle: widget.customQuizTitle ?? LiveQuizState.activeQuizTitle.value,
            questionAnalysis: questionAnalysis,
          ),
        ),
      );
    }
  }

  Widget _buildFloatingCameraProctorTile(bool isDark) {
    if (_isCameraCollapsed) {
      return GestureDetector(
        onTap: () => setState(() => _isCameraCollapsed = false),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.redAccent, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.redAccent.withValues(alpha: 0.3),
                blurRadius: 6,
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fiber_manual_record, color: Colors.red, size: 10),
              SizedBox(width: 4),
              Text(
                'AI CAM ON',
                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: 105,
      height: 135,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.redAccent, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.redAccent.withValues(alpha: 0.25),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (_isCameraReady && _cameraController != null && _cameraController!.value.isInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _cameraController!.value.previewSize?.height ?? 100,
                  height: _cameraController!.value.previewSize?.width ?? 130,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            )
          else
            Container(
              color: const Color(0xFF0F172A),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.face, color: Colors.white54, size: 36),
                    SizedBox(height: 4),
                    Text(
                      'AI SCANNING',
                      style: TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

          // Face Bounding Box
          Center(
            child: Container(
              width: 70,
              height: 90,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5), width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),

          // Red REC Badge
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fiber_manual_record, color: Colors.white, size: 7),
                  SizedBox(width: 3),
                  Text(
                    'REC',
                    style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),

          // Collapse Button
          Positioned(
            top: 2,
            right: 2,
            child: InkWell(
              onTap: () => setState(() => _isCameraCollapsed = true),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.close, color: Colors.white70, size: 12),
              ),
            ),
          ),

          // Bottom AI Proctor Tag
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 2),
              color: Colors.black.withValues(alpha: 0.7),
              child: const Text(
                'AI PROCTOR • LIVE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 7.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final currentQ = _questions[_currentIndex];
    final isBookmarked = _bookmarks.contains(_currentIndex);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _confirmSubmit();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            'પ્રશ્ન ${_currentIndex + 1}/${_questions.length}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          actions: [
            IconButton(
              tooltip: 'પ્રશ્ન નેવિગેટર (Question Grid)',
              icon: const Icon(Icons.grid_view_rounded),
              onPressed: _openQuestionNavigator,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    _formatTimer(_remainingSeconds),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                isBookmarked ? Icons.bookmark : Icons.bookmark_outline,
                color: isBookmarked ? Colors.amber : Colors.white,
              ),
              onPressed: () {
                AppAudio.playMark();
                setState(() {
                  if (isBookmarked) {
                    _bookmarks.remove(_currentIndex);
                  } else {
                    _bookmarks.add(_currentIndex);
                  }
                });
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                // Question Progress Bar
                LinearProgressIndicator(
                  value: (_currentIndex + 1) / _questions.length,
                  backgroundColor: isDark ? Colors.white10 : Colors.black12,
                  valueColor: AlwaysStoppedAnimation<Color>(primary),
                ),

                // AI Camera Monitoring Live Banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    border: const Border(
                      bottom: BorderSide(color: Colors.redAccent, width: 0.6),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.fiber_manual_record, color: Colors.red, size: 10),
                      SizedBox(width: 6),
                      Text(
                        'LIVE AI CAMERA PROCTORING • કેમેરા નિરીક્ષણ ચાલુ છે',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          currentQ['question'] ?? 'પ્રશ્ન લોડ થઈ રહ્યો છે...',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.4),
                        ),
                        QuestionDiagramView(
                          question: currentQ is Map<String, dynamic>
                              ? currentQ
                              : Map<String, dynamic>.from(currentQ),
                        ),
                        const SizedBox(height: 12),

                        // Options List
                        ...List.generate(
                          (currentQ['options'] as List<dynamic>? ?? []).length,
                          (optIndex) {
                            final optionText = currentQ['options'][optIndex];
                            final isSelected = _answers[_currentIndex] == optIndex;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? primary.withValues(alpha: 0.12)
                                    : (isDark ? const Color(0xFF131B2E) : Colors.white),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected ? primary : (isDark ? Colors.white12 : Colors.black12),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: InkWell(
                                onTap: () {
                                  AppAudio.playTap();
                                  setState(() {
                                    _answers[_currentIndex] = optIndex;
                                  });
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 14,
                                        backgroundColor: isSelected ? primary : Colors.transparent,
                                        child: Text(
                                          String.fromCharCode(65 + optIndex), // A, B, C, D
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Text(
                                          optionText.toString(),
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom Navigation Controls
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF131B2E) : Colors.white,
                    border: Border(
                      top: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (_currentIndex > 0)
                        OutlinedButton(
                          onPressed: () {
                            AppAudio.playNext();
                            setState(() {
                              _currentIndex--;
                            });
                          },
                          child: const Text('પાછળ'),
                        )
                      else
                        const SizedBox(width: 60),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: _openQuestionNavigator,
                        icon: const Icon(Icons.grid_view_rounded, size: 16),
                        label: Text('${_currentIndex + 1}/${_questions.length}'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const Spacer(),
                      if (_currentIndex < _questions.length - 1)
                        FilledButton(
                          onPressed: () {
                            AppAudio.playNext();
                            setState(() {
                              _currentIndex++;
                            });
                          },
                          child: const Text('આગળ'),
                        )
                      else
                        FilledButton.icon(
                          onPressed: _confirmSubmit,
                          icon: const Icon(Icons.check),
                          label: const Text('જમા કરો'),
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            // Floating Live Camera Proctoring Tile (Top Right)
            Positioned(
              top: 8,
              right: 12,
              child: _buildFloatingCameraProctorTile(isDark),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// QUESTION NAVIGATOR MODAL SHEET (Matches User's UI Screenshot)
// -------------------------------------------------------------
class _QuestionNavigatorSheet extends StatefulWidget {
  final int totalQuestions;
  final int currentIndex;
  final Map<int, int> answers;
  final Set<int> bookmarks;
  final ValueChanged<int> onSelectQuestion;
  final VoidCallback onSubmit;

  const _QuestionNavigatorSheet({
    required this.totalQuestions,
    required this.currentIndex,
    required this.answers,
    required this.bookmarks,
    required this.onSelectQuestion,
    required this.onSubmit,
  });

  @override
  State<_QuestionNavigatorSheet> createState() => _QuestionNavigatorSheetState();
}

class _QuestionNavigatorSheetState extends State<_QuestionNavigatorSheet> {
  int _filterIndex = 0; // 0: બધા (All), 1: આપેલ (Answered), 2: બાકી (Pending), 3: રિવ્યુ (Review)

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final answeredCount = widget.answers.length;
    final reviewCount = widget.bookmarks.length;
    final pendingCount = widget.totalQuestions - answeredCount;

    // Filter questions based on selected tab
    final List<int> displayIndices = [];
    for (int i = 0; i < widget.totalQuestions; i++) {
      if (_filterIndex == 1) {
        if (widget.answers.containsKey(i)) displayIndices.add(i);
      } else if (_filterIndex == 2) {
        if (!widget.answers.containsKey(i)) displayIndices.add(i);
      } else if (_filterIndex == 3) {
        if (widget.bookmarks.contains(i)) displayIndices.add(i);
      } else {
        displayIndices.add(i);
      }
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFF1E293B),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Handle bar
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Header Row: Grid Icon, Title, Total Count Pill
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.grid_view_rounded, color: Color(0xFF818CF8), size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    'પ્રશ્ન નેવિગેટર',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'કુલ: ${widget.totalQuestions}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Status Legend Row (Answered, Review, Pending)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildLegendItem(const Color(0xFF10B981), 'ઉત્તર આપેલ ($answeredCount)'),
                    _buildLegendItem(const Color(0xFFF59E0B), 'રિવ્યુ ($reviewCount)'),
                    _buildLegendItem(Colors.white38, 'બાકી ($pendingCount)'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Filter Tabs: [બધા] [આપેલ] [બાકી] [રિવ્યુ]
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    _buildFilterTab(0, 'બધા'),
                    _buildFilterTab(1, 'આપેલ'),
                    _buildFilterTab(2, 'બાકી'),
                    _buildFilterTab(3, 'રિવ્યુ'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Questions 5-Column Grid
            Expanded(
              child: displayIndices.isEmpty
                  ? const Center(
                      child: Text(
                        'આ કેટેગરીમાં કોઈ પ્રશ્નો નથી.',
                        style: TextStyle(color: Colors.white60, fontSize: 13),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.15,
                      ),
                      itemCount: displayIndices.length,
                      itemBuilder: (context, idx) {
                        final qIndex = displayIndices[idx];
                        final isCurrent = qIndex == widget.currentIndex;
                        final isAnswered = widget.answers.containsKey(qIndex);
                        final isBookmarked = widget.bookmarks.contains(qIndex);

                        Color bgColor;
                        Color textColor;
                        Color borderColor;

                        if (isCurrent) {
                          bgColor = Colors.white;
                          textColor = const Color(0xFF4338CA);
                          borderColor = const Color(0xFF818CF8);
                        } else if (isAnswered) {
                          bgColor = const Color(0xFF10B981).withValues(alpha: 0.22);
                          textColor = const Color(0xFF34D399);
                          borderColor = const Color(0xFF10B981);
                        } else if (isBookmarked) {
                          bgColor = const Color(0xFFF59E0B).withValues(alpha: 0.22);
                          textColor = const Color(0xFFFBBF24);
                          borderColor = const Color(0xFFF59E0B);
                        } else {
                          bgColor = Colors.white.withValues(alpha: 0.08);
                          textColor = Colors.white70;
                          borderColor = Colors.white.withValues(alpha: 0.12);
                        }

                        return InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            widget.onSelectQuestion(qIndex);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(
                              color: bgColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: borderColor,
                                width: isCurrent ? 2 : 1,
                              ),
                              boxShadow: isCurrent
                                  ? [
                                      BoxShadow(
                                        color: Colors.white.withValues(alpha: 0.25),
                                        blurRadius: 6,
                                      ),
                                    ]
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Text(
                                  '${qIndex + 1}',
                                  style: TextStyle(
                                    fontWeight: isCurrent ? FontWeight.w900 : FontWeight.bold,
                                    fontSize: 13,
                                    color: textColor,
                                  ),
                                ),
                                if (isBookmarked && !isCurrent)
                                  const Positioned(
                                    top: 2,
                                    right: 2,
                                    child: Icon(Icons.bookmark, size: 9, color: Color(0xFFF59E0B)),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Submit Exam Action Button (at bottom of Navigator Sheet)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onSubmit();
                  },
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text(
                    'કસોટી જમા કરો',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color dotColor, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildFilterTab(int index, String label) {
    final isSelected = _filterIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filterIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF334155) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.normal,
              color: isSelected ? Colors.white : Colors.white60,
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// RESULT SCREEN
// -------------------------------------------------------------
class ResultScreen extends StatefulWidget {
  final int score;
  final int total;
  final int pct;
  final bool autoSubmitted;
  final String studentName;
  final String quizTitle;
  final List<dynamic> questionAnalysis;

  const ResultScreen({
    super.key,
    required this.score,
    required this.total,
    required this.pct,
    required this.autoSubmitted,
    required this.studentName,
    this.quizTitle = 'NMMS આદર્શ પેપર 52',
    this.questionAnalysis = const [],
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  @override
  void initState() {
    super.initState();
    AppAudio.playCelebration();
  }

  @override
  Widget build(BuildContext context) {
    final score = widget.score;
    final total = widget.total;
    final pct = widget.pct;
    final autoSubmitted = widget.autoSubmitted;
    final studentName = widget.studentName;
    final isPassed = score >= ((total * 0.40).round());
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final qList = widget.questionAnalysis;
    final incorrectCount = qList.where((q) => q['status'] == 'incorrect').length;
    final unattemptedCount = qList.where((q) => q['status'] == 'unattempted').length;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (autoSubmitted)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                    ),
                    child: const Text(
                      '🚨 એપ ૩ વખત મિનિમાઇઝ કરવાના કારણે કસોટી આપમેળે જમા થઈ ગઈ છે.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),

                Icon(
                  isPassed ? Icons.emoji_events : Icons.verified,
                  size: 80,
                  color: isPassed ? Colors.amber : Colors.blue,
                ),
                const SizedBox(height: 16),
                Text(
                  isPassed ? 'અભિનંદન! પરીક્ષા પાસ 🏆' : 'કસોટી સફળતાપૂર્વક પૂર્ણ!',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  studentName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 24),

                // Score Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF131B2E) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.black12,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$score / $total',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ટકાવારી: $pct%',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const Divider(height: 28),

                      // Breakdown Pills
                      if (qList.isNotEmpty) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '✅ સાચા: $score',
                                style: const TextStyle(
                                  color: Color(0xFF10B981),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '❌ ખોટા: $incorrectCount',
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '⚪ બાકી: $unattemptedCount',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],

                      const Text(
                        'NMMS પાસ થવા માટે ઓછામાં ઓછા 72 ગુણ જરૂરી છે.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Button 1: Review Questions & Answers (Requested by User)
                if (qList.isNotEmpty) ...[
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ExamReviewScreen(
                            quizTitle: widget.quizTitle,
                            score: score,
                            total: total,
                            questionAnalysis: qList,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.analytics_outlined),
                    label: const Text('પ્રશ્નો, ઉત્તરો અને સમય વિશ્લેષણ જુઓ'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  icon: const Icon(Icons.home),
                  label: const Text('હોમ પેજ પર જાઓ'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// EXAM REVIEW SCREEN (Questions, Answers, Time Spent Per Question)
// -------------------------------------------------------------
class ExamReviewScreen extends StatefulWidget {
  final String quizTitle;
  final int score;
  final int total;
  final List<dynamic> questionAnalysis;

  const ExamReviewScreen({
    super.key,
    required this.quizTitle,
    required this.score,
    required this.total,
    required this.questionAnalysis,
  });

  @override
  State<ExamReviewScreen> createState() => _ExamReviewScreenState();
}

class _ExamReviewScreenState extends State<ExamReviewScreen> {
  int _filterIndex = 0; // 0: બધા, 1: ખોટા, 2: સાચા, 3: ખાલી રાખેલ

  String _formatSeconds(int seconds) {
    if (seconds < 60) {
      return '$seconds સેકન્ડ';
    }
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m મિ. $s સેકન્ડ';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    final allList = widget.questionAnalysis;
    final correctList = allList.where((q) => q['status'] == 'correct').toList();
    final incorrectList = allList.where((q) => q['status'] == 'incorrect').toList();
    final unattemptedList = allList.where((q) => q['status'] == 'unattempted').toList();

    List<dynamic> displayedList;
    if (_filterIndex == 1) {
      displayedList = incorrectList;
    } else if (_filterIndex == 2) {
      displayedList = correctList;
    } else if (_filterIndex == 3) {
      displayedList = unattemptedList;
    } else {
      displayedList = allList;
    }

    // Calculate total & average time
    int totalTimeSeconds = 0;
    for (var q in allList) {
      totalTimeSeconds += (q['timeSpentSeconds'] as int? ?? 0);
    }
    final avgSeconds = allList.isNotEmpty ? (totalTimeSeconds / allList.length).round() : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('પેપર વિશ્લેષણ અને સોલ્યુશન'),
      ),
      body: Column(
        children: [
          // Stat Summary Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF131B2E) : const Color(0xFFF1F5F9),
              border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.quizTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildStatChip('સાચા: ${correctList.length}', const Color(0xFF10B981)),
                    const SizedBox(width: 8),
                    _buildStatChip('ખોટા: ${incorrectList.length}', Colors.red),
                    const SizedBox(width: 8),
                    _buildStatChip('ખાલી: ${unattemptedList.length}', Colors.grey),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '⏱️ સરેરાશ: $avgSeconds સે.',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Filter Segmented Buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildFilterButton(0, 'બધા (${allList.length})'),
                const SizedBox(width: 6),
                _buildFilterButton(1, 'ખોટા (${incorrectList.length})'),
                const SizedBox(width: 6),
                _buildFilterButton(2, 'સાચા (${correctList.length})'),
                const SizedBox(width: 6),
                _buildFilterButton(3, 'ખાલી (${unattemptedList.length})'),
              ],
            ),
          ),

          const Divider(height: 1),

          // Question Cards List
          Expanded(
            child: displayedList.isEmpty
                ? const Center(
                    child: Text(
                      'આ કેટેગરીમાં કોઈ પ્રશ્નો નથી.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: displayedList.length,
                    itemBuilder: (context, index) {
                      final item = displayedList[index];
                      final qIndex = (item['index'] as int? ?? index) + 1;
                      final status = item['status'] as String? ?? 'unattempted';
                      final timeSpent = item['timeSpentSeconds'] as int? ?? 0;
                      final studentAns = item['studentAnswer'] as int?;
                      final correctAns = item['correctAnswer'] as int? ?? 0;
                      final options = (item['options'] as List<dynamic>? ?? []);

                      Color statusColor;
                      String statusText;
                      IconData statusIcon;

                      if (status == 'correct') {
                        statusColor = const Color(0xFF10B981);
                        statusText = 'સાચો ઉત્તર';
                        statusIcon = Icons.check_circle_outline;
                      } else if (status == 'incorrect') {
                        statusColor = Colors.red;
                        statusText = 'ખોટો ઉત્તર';
                        statusIcon = Icons.cancel_outlined;
                      } else {
                        statusColor = Colors.grey;
                        statusText = 'ખાલી રાખેલ';
                        statusIcon = Icons.help_outline;
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF131B2E) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.4),
                            width: 1.2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Card Header: Question Number, Status, Time Spent
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'પ્રશ્ન $qIndex',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                      color: primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(statusIcon, size: 14, color: statusColor),
                                      const SizedBox(width: 4),
                                      Text(
                                        statusText,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                          color: statusColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.timer_outlined, size: 12, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatSeconds(timeSpent),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Question Text
                            Text(
                              item['question'] as String? ?? '',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.35),
                            ),

                            QuestionDiagramView(
                              question: item is Map<String, dynamic>
                                  ? item
                                  : Map<String, dynamic>.from(item),
                              isReview: true,
                            ),

                            const SizedBox(height: 12),

                            // Options List with Visual Highlight
                            ...List.generate(options.length, (optIdx) {
                              final optText = options[optIdx].toString();
                              final isStudentChoice = studentAns == optIdx;
                              final isCorrectChoice = correctAns == optIdx;

                              Color optBg;
                              Color optBorder;
                              Color optTextColor;
                              IconData? optIcon;

                              if (isCorrectChoice) {
                                optBg = const Color(0xFF10B981).withValues(alpha: 0.15);
                                optBorder = const Color(0xFF10B981);
                                optTextColor = const Color(0xFF047857);
                                optIcon = Icons.check_circle;
                              } else if (isStudentChoice) {
                                optBg = Colors.red.withValues(alpha: 0.12);
                                optBorder = Colors.redAccent;
                                optTextColor = Colors.red.shade700;
                                optIcon = Icons.cancel;
                              } else {
                                optBg = isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC);
                                optBorder = isDark ? Colors.white10 : Colors.black12;
                                optTextColor = isDark ? Colors.white70 : Colors.black87;
                              }

                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: optBg,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: optBorder,
                                    width: (isCorrectChoice || isStudentChoice) ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 12,
                                      backgroundColor: isCorrectChoice
                                          ? const Color(0xFF10B981)
                                          : (isStudentChoice ? Colors.red : (isDark ? Colors.white12 : Colors.black12)),
                                      child: Text(
                                        String.fromCharCode(65 + optIdx),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: (isCorrectChoice || isStudentChoice)
                                              ? Colors.white
                                              : (isDark ? Colors.white70 : Colors.black87),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        optText,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: (isCorrectChoice || isStudentChoice)
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: isDark && !isCorrectChoice && !isStudentChoice
                                              ? Colors.white70
                                              : optTextColor,
                                        ),
                                      ),
                                    ),
                                    if (optIcon != null) ...[
                                      const SizedBox(width: 6),
                                      Icon(optIcon, size: 16, color: optBorder),
                                    ],
                                  ],
                                ),
                              );
                            }),

                            const SizedBox(height: 6),

                            // Footer Note
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    studentAns != null
                                        ? 'તમારો ઉત્તર: ${String.fromCharCode(65 + studentAns)}'
                                        : 'તમારો ઉત્તર: ખાલી રાખેલ',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: statusColor,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (item['isGrace'] == true) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.amber, width: 0.8),
                                      ),
                                      child: const Text(
                                        'ગ્રેસ ગુણ (પ્રશ્નમાં ક્ષતિ)',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.amber,
                                        ),
                                      ),
                                    ),
                                  ] else ...[
                                    Text(
                                      'સાચો ઉત્તર: ${String.fromCharCode(65 + correctAns)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF10B981),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (item['explanation'] != null && (item['explanation'] as String).trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                                ),
                                child: Text(
                                  '💡 સમજૂતી: ${item['explanation']}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.blue.shade200 : Colors.blue.shade900,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildFilterButton(int index, String label) {
    final isSelected = _filterIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _filterIndex = index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.white : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }
}
