import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

// ============ MODELS & GLOBAL STATE ============

// ServiceUser: User data model
class ServiceUser {
  String name;
  String email;
  String phone;
  String password;

  ServiceUser({
    required this.name,
    required this.email,
    required this.phone,
    required this.password,
  });

  ServiceUser copyWith({
    String? name,
    String? email,
    String? phone,
    String? password,
  }) {
    return ServiceUser(
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      password: password ?? this.password,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'password': password, // Will be hashed before saving
    };
  }

  factory ServiceUser.fromJson(Map<String, dynamic> json) {
    return ServiceUser(
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      password: json['password'] ?? '',
    );
  }
}

// RegisteredUser: Stores registered user credentials
class RegisteredUser {
  final String email;
  String password;
  ServiceUser userData;

  RegisteredUser({
    required this.email,
    required this.password,
    required this.userData,
  });

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'password': password, // Hashed password
      'userData': userData.toJson(),
    };
  }

  factory RegisteredUser.fromJson(Map<String, dynamic> json) {
    return RegisteredUser(
      email: json['email'] ?? '',
      password: json['password'] ?? '',
      userData: ServiceUser.fromJson(json['userData'] ?? {}),
    );
  }
}

// ServiceBooking: Booking data model
class ServiceBooking {
  final String serviceName;
  final String province;
  final DateTime dateTime;
  final String notes;
  final String userEmail; // Associate booking with user
  bool isCancelled;

  ServiceBooking({
    required this.serviceName,
    required this.province,
    required this.dateTime,
    required this.notes,
    required this.userEmail,
    this.isCancelled = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'serviceName': serviceName,
      'province': province,
      'dateTime': dateTime.toIso8601String(),
      'notes': notes,
      'userEmail': userEmail,
      'isCancelled': isCancelled,
    };
  }

  factory ServiceBooking.fromJson(Map<String, dynamic> json) {
    return ServiceBooking(
      serviceName: json['serviceName'] ?? '',
      province: json['province'] ?? '',
      dateTime: DateTime.parse(json['dateTime'] ?? DateTime.now().toIso8601String()),
      notes: json['notes'] ?? '',
      userEmail: json['userEmail'] ?? '', // Default to empty for backward compatibility
      isCancelled: json['isCancelled'] ?? false,
    );
  }
}

// ServiceNotification: Notification data model
class ServiceNotification {
  final String message;
  final DateTime createdAt;

  ServiceNotification({
    required this.message,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'message': message,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ServiceNotification.fromJson(Map<String, dynamic> json) {
    return ServiceNotification(
      message: json['message'] ?? '',
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
    );
  }
}

// ServiceAppState: App state management
class ServiceAppState extends ChangeNotifier {
  ServiceUser? currentUser;
  final List<ServiceBooking> bookings = [];
  final List<ServiceNotification> notifications = [];
  final Map<String, RegisteredUser> registeredUsers = {}; // email -> RegisteredUser
  bool _isLoading = false;

  // Hash password using SHA-256
  String _hashPassword(String password) {
    var bytes = utf8.encode(password);
    var digest = sha256.convert(bytes);
    return digest.toString();
  }

  // Verify password against hash
  bool _verifyPassword(String password, String hash) {
    return _hashPassword(password) == hash;
  }

  // Load data from SharedPreferences
  Future<void> loadData() async {
    if (_isLoading) return;
    _isLoading = true;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load registered users
      final usersJson = prefs.getString('registeredUsers');
      if (usersJson != null) {
        final Map<String, dynamic> usersMap = json.decode(usersJson);
        registeredUsers.clear();
        usersMap.forEach((email, userJson) {
          registeredUsers[email] = RegisteredUser.fromJson(userJson);
        });
      }

      // Load bookings
      final bookingsJson = prefs.getString('bookings');
      if (bookingsJson != null) {
        final List<dynamic> bookingsList = json.decode(bookingsJson);
        bookings.clear();
        bookings.addAll(bookingsList.map((b) => ServiceBooking.fromJson(b)));
      }

      // Load notifications
      final notificationsJson = prefs.getString('notifications');
      if (notificationsJson != null) {
        final List<dynamic> notificationsList = json.decode(notificationsJson);
        notifications.clear();
        notifications.addAll(notificationsList.map((n) => ServiceNotification.fromJson(n)));
      }

      // Load current user email (for auto-login)
      // Must load this AFTER registeredUsers are loaded
      final currentUserEmail = prefs.getString('currentUserEmail');
      if (currentUserEmail != null && currentUserEmail.isNotEmpty) {
        final registeredUser = registeredUsers[currentUserEmail.toLowerCase()];
        if (registeredUser != null) {
          currentUser = registeredUser.userData;
        } else {
          // User not found in registeredUsers, clear the saved email
          await prefs.remove('currentUserEmail');
        }
      }

      notifyListeners();
    } catch (e) {
      print('Error loading data: $e');
    } finally {
      _isLoading = false;
    }
  }

  // Save data to SharedPreferences
  Future<void> saveData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Save registered users
      final usersMap = <String, dynamic>{};
      registeredUsers.forEach((email, user) {
        usersMap[email] = user.toJson();
      });
      await prefs.setString('registeredUsers', json.encode(usersMap));

      // Save bookings
      final bookingsList = bookings.map((b) => b.toJson()).toList();
      await prefs.setString('bookings', json.encode(bookingsList));

      // Save notifications
      final notificationsList = notifications.map((n) => n.toJson()).toList();
      await prefs.setString('notifications', json.encode(notificationsList));

      // Save current user email
      if (currentUser != null) {
        await prefs.setString('currentUserEmail', currentUser!.email.toLowerCase());
      } else {
        await prefs.remove('currentUserEmail');
      }
    } catch (e) {
      print('Error saving data: $e');
    }
  }

  // registerUser: Register new user
  void registerUser(ServiceUser user) {
    final hashedPassword = _hashPassword(user.password);
    final userWithHashedPassword = ServiceUser(
      name: user.name,
      email: user.email,
      phone: user.phone,
      password: hashedPassword,
    );
    
    registeredUsers[user.email.toLowerCase()] = RegisteredUser(
      email: user.email.toLowerCase(),
      password: hashedPassword,
      userData: userWithHashedPassword,
    );
    currentUser = userWithHashedPassword;
    saveData();
    notifyListeners();
  }

  // getUserByEmail: Get user by email
  RegisteredUser? getUserByEmail(String email) {
    return registeredUsers[email.toLowerCase()];
  }

  // validateLogin: Validate login credentials
  bool validateLogin(String email, String password) {
    final user = getUserByEmail(email);
    if (user == null) return false;
    
    // Hash the input password
    final inputHash = _hashPassword(password);
    
    // Check if stored password is a hash (64 hex characters)
    // SHA-256 produces 64 hex characters
    final isStoredPasswordHashed = user.password.length == 64 && 
        RegExp(r'^[a-f0-9]{64}$', caseSensitive: false).hasMatch(user.password);
    
    if (isStoredPasswordHashed) {
      // Compare hashed input with stored hash (secure)
      return inputHash == user.password;
    } else {
      // Backward compatibility: compare directly (for old unhashed passwords)
      return user.password == password;
    }
  }

  // loginUser: Set current user and save session to SharedPreferences
  void loginUser(ServiceUser user) {
    currentUser = user;
    saveData(); // Persist session
    notifyListeners();
  }

  // logoutUser: Clear current user session from memory and SharedPreferences
  void logoutUser() {
    currentUser = null;
    saveData(); // Clear session from cache
    notifyListeners();
  }

  // updateUserProfile: Update user profile info
  void updateUserProfile(String email, String name, String phone) {
    final registeredUser = registeredUsers[email.toLowerCase()];
    if (registeredUser != null) {
      registeredUser.userData.name = name;
      registeredUser.userData.phone = phone;
      if (currentUser?.email.toLowerCase() == email.toLowerCase()) {
        currentUser!.name = name;
        currentUser!.phone = phone;
      }
      saveData();
      notifyListeners();
    }
  }

  // updateEmailAndPassword: Update email and/or password
  void updateEmailAndPassword(String oldEmail, String newEmail, String? newPassword) {
    final oldEmailLower = oldEmail.toLowerCase();
    final newEmailLower = newEmail.toLowerCase();
    final registeredUser = registeredUsers[oldEmailLower];
    
    if (registeredUser == null) return;
    
    // Hash new password if provided
    final hashedNewPassword = newPassword != null && newPassword.isNotEmpty
        ? _hashPassword(newPassword)
        : null;
    
    // If email changed, update the map key
    if (oldEmailLower != newEmailLower) {
      // Check if new email already exists
      if (registeredUsers.containsKey(newEmailLower)) {
        throw Exception('Email already in use');
      }
      
      // Create new user data with updated email
      final updatedUserData = registeredUser.userData.copyWith(
        email: newEmail,
        password: hashedNewPassword ?? registeredUser.userData.password,
      );
      
      // Create new registered user
      final newRegisteredUser = RegisteredUser(
        email: newEmailLower,
        password: hashedNewPassword ?? registeredUser.password,
        userData: updatedUserData,
      );
      
      // Remove old entry and add new one
      registeredUsers.remove(oldEmailLower);
      registeredUsers[newEmailLower] = newRegisteredUser;
      
      // Update current user if it's the logged-in user
      if (currentUser?.email.toLowerCase() == oldEmailLower) {
        currentUser = updatedUserData;
      }
    } else {
      // Only password changed
      if (hashedNewPassword != null) {
        final updatedUserData = registeredUser.userData.copyWith(
          password: hashedNewPassword,
        );
        // Create new registered user with updated password
        final newRegisteredUser = RegisteredUser(
          email: registeredUser.email,
          password: hashedNewPassword,
          userData: updatedUserData,
        );
        registeredUsers[oldEmailLower] = newRegisteredUser;
        
        // Update current user if it's the logged-in user
        if (currentUser?.email.toLowerCase() == oldEmailLower) {
          currentUser = updatedUserData;
        }
      }
    }
    
    saveData();
    notifyListeners();
  }

  // addBooking: Add new booking
  void addBooking(ServiceBooking booking) {
    // Ensure booking has userEmail from currentUser if not already set
    final bookingWithUser = booking.userEmail.isEmpty && currentUser != null
        ? ServiceBooking(
            serviceName: booking.serviceName,
            province: booking.province,
            dateTime: booking.dateTime,
            notes: booking.notes,
            userEmail: currentUser!.email.toLowerCase(),
            isCancelled: booking.isCancelled,
          )
        : booking;
    
    bookings.add(bookingWithUser);
    notifications.add(
      ServiceNotification(
        message:
            'Booked ${bookingWithUser.serviceName} in ${bookingWithUser.province} on ${bookingWithUser.dateTime.day}/${bookingWithUser.dateTime.month}/${bookingWithUser.dateTime.year} at ${TimeOfDay.fromDateTime(bookingWithUser.dateTime).format(GlobalNavigator.key.currentContext!)}',
        createdAt: DateTime.now(),
      ),
    );
    saveData();
    notifyListeners();
  }

  // cancelBooking: Cancel existing booking
  void cancelBooking(ServiceBooking booking) {
    final index = bookings.indexOf(booking);
    if (index != -1) {
      // Mark as cancelled instead of removing so it appears in all screens
      bookings[index].isCancelled = true;
    }

    // Add cancellation notification (keep the original "Booked" notification visible)
    notifications.add(
      ServiceNotification(
        message:
            'Cancelled ${booking.serviceName} in ${booking.province} on ${booking.dateTime.day}/${booking.dateTime.month}/${booking.dateTime.year}',
        createdAt: DateTime.now(),
      ),
    );
    saveData();
    notifyListeners();
  }
}

// ============ GLOBAL NAVIGATOR KEY ============

// GlobalNavigator: Global navigator key
class GlobalNavigator {
  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();
}

// ============ CONSTANT DATA ============

const List<String> provinces = [
  'Cairo',
  'Giza',
  'Alexandria',
  'Qalyubia',
  'Sharqia',
  'Gharbia',
];

// ServiceData: Static service data
class ServiceData {
  static const List<Map<String, dynamic>> services = [
    {
      'id': 'electricity',
      'name': 'Electricity',
      'description': 'Electrical maintenance – repairs – installation',
      'details':
          'Complete electrical services including fault repairs, new panel installation, cable extension, and electrical device installation with work guarantee.',
      'color': Colors.yellow,
      'icon': Icons.electric_bolt,
      'subcategories': [
        {
          'id': 'elec_repair',
          'name': 'Electrical Repairs',
          'description': 'Fix electrical faults and issues',
         'image': 'img/electrical repairs.jpg',
          'iconImage': 'assets/images/elec_repair_icon.png',
        },
        {
          'id': 'elec_installation',
          'name': 'Panel Installation',
          'description': 'Install new electrical panels',
          'image': 'https://images.unsplash.com/photo-1621905251918-48416bd8575a?w=400&h=300&fit=crop',
          'iconImage': 'assets/images/elec_installation_icon.png',
        },
        {
          'id': 'elec_wiring',
          'name': 'Wiring & Cabling',
          'description': 'Wire extension and cable installation',
          'image': 'img/wire.jpg',
          'iconImage': 'assets/images/elec_wiring_icon.png',
        },
        {
          'id': 'elec_appliance',
          'name': 'Appliance Installation',
          'description': 'Install electrical appliances',
          'image': 'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=400&h=300&fit=crop',
          'iconImage': 'assets/images/elec_appliance_icon.png',
        },
      ],
    },
    {
      'id': 'plumbing',
      'name': 'Plumbing',
      'description': 'Leak repairs – faucet installation',
      'details':
          'Professional plumbing services for leak repairs and pipe blockages, installation of new faucets and mixers, and periodic maintenance of water networks.',
      'color': Colors.blue,
      'icon': Icons.water_damage,
      'subcategories': [
        {
          'id': 'plumb_leak',
          'name': 'Leak Repairs',
          'description': 'Fix water leaks and drips',
          'image': 'img/leak repair.jpg',

          'iconImage': 'assets/images/plumb_leak_icon.png',
        },
        {
          'id': 'plumb_faucet',
          'name': 'Faucet Installation',
          'description': 'Install new faucets and taps',
        'image': 'img/faucet installation.jpg',

          'iconImage': 'assets/images/plumb_faucet_icon.png',
        },
        {
          'id': 'plumb_pipe',
          'name': 'Pipe Repair',
          'description': 'Fix blocked or broken pipes',
          'image': 'https://tse2.mm.bing.net/th/id/OIP.dfG1We_13ZpMsJOOlXBJPQHaEK?cb=ucfimg2&ucfimg=1&rs=1&pid=ImgDetMain&o=7&rm=3',
          'iconImage': 'assets/images/plumb_pipe_icon.png',
        },
        {
          'id': 'plumb_toilet',
          'name': 'Toilet Services',
          'description': 'Toilet repair and installation',
          'image': 'img/toilet repair.jpg',

          'iconImage': 'assets/images/plumb_toilet_icon.png',
        },
      ],
    },
    {
      'id': 'ac',
      'name': 'Air Conditioning',
      'description': 'AC installation and maintenance',
      'details':
          'Installation and maintenance of all types of air conditioning units, regular cleaning and maintenance, and refrigerant charging with comprehensive performance check.',
      'color': Colors.cyan,
      'icon': Icons.ac_unit,
      'subcategories': [
        {
          'id': 'ac_install',
          'name': 'AC Installation',
          'description': 'Install new AC units',
          'image': 'img/AC installation.jpg',
          'iconImage': 'assets/images/ac_install_icon.png',
        },
        {
          'id': 'ac_repair',
          'name': 'AC Repair',
          'description': 'Fix AC problems and issues',
          'image': 'img/Ac Repair.jpg',

          'iconImage': 'assets/images/ac_repair_icon.png',
        },
        {
          'id': 'ac_cleaning',
          'name': 'AC Cleaning',
          'description': 'Deep cleaning and maintenance',
'image': 'img/Ac Cleaning.jpg',

          'iconImage': 'assets/images/ac_cleaning_icon.png',
        },
        {
          'id': 'ac_gas',
          'name': 'Gas Charging',
          'description': 'Refrigerant gas refill',
          'image': 'img/Gas Charging.jpg',

          'iconImage': 'assets/images/ac_gas_icon.png',
        },
      ],
    },
    {
      'id': 'carpentry',
      'name': 'Carpentry',
      'description': 'Manufacturing and installation of furniture and wooden works',
      'details':
          'Carpentry services including manufacturing and installation of doors, windows, furniture, and kitchens with highest quality and custom designs.',
      'color': Colors.brown,
      'icon': Icons.chair_alt,
      'subcategories': [
        {
          'id': 'carp_door',
          'name': 'Doors & Windows',
          'description': 'Install doors and windows',
          'image': 'https://images.unsplash.com/photo-1600607687644-c7171b42498f?w=400&h=300&fit=crop',
          'iconImage': 'assets/images/carp_door_icon.png',
        },
        {
          'id': 'carp_furniture',
          'name': 'Furniture Making',
          'description': 'Custom furniture manufacturing',
          'image': 'https://images.unsplash.com/photo-1506439773649-6e0eb8cfb237?w=400&h=300&fit=crop',
          'iconImage': 'assets/images/carp_furniture_icon.png',
        },
        {
          'id': 'carp_kitchen',
          'name': 'Kitchen Cabinets',
          'description': 'Design and install kitchen cabinets',
          'image': 'https://images.unsplash.com/photo-1556912172-45b7abe8b7e1?w=400&h=300&fit=crop',
          'iconImage': 'assets/images/carp_kitchen_icon.png',
        },
        {
          'id': 'carp_repair',
          'name': 'Furniture Repair',
          'description': 'Repair damaged furniture',
      'image': 'img/fixfurn.jpg',

          'iconImage': 'assets/images/carp_repair_icon.png',
        },
      ],
    },
    {
      'id': 'car_wash',
      'name': 'Home Car Wash',
      'description': 'Professional car washing and detailing at your location',
      'details':
          'Complete car wash and detailing services at your home or office. Includes exterior wash, interior cleaning, waxing, and polishing. We bring all equipment to you.',
      'color': Colors.blueGrey,
      'icon': Icons.local_car_wash,
      'subcategories': [
        {
          'id': 'wash_basic',
          'name': 'Basic Wash',
          'description': 'Exterior wash and dry',
          'image': 'img/Basic Wash.jpg',

          'iconImage': 'assets/images/wash_basic_icon.png',
        },
        {
          'id': 'wash_full',
          'name': 'Full Service',
          'description': 'Exterior + interior cleaning',
          'image': 'img/Full Service.jpg',
          'iconImage': 'assets/images/wash_full_icon.png',
        },
        {
          'id': 'wash_detailing',
          'name': 'Car Detailing',
          'description': 'Complete detailing and polishing',
          'image': 'img/Car detailing.jpg',

          'iconImage': 'assets/images/wash_detailing_icon.png',
        },
        {
          'id': 'wash_wax',
          'name': 'Wax & Polish',
          'description': 'Waxing and paint protection',
          'image': 'https://images.unsplash.com/photo-1492144534655-ae79c964c9d7?w=400&h=300&fit=crop',
          'iconImage': 'assets/images/wash_wax_icon.png',
        },
      ],
    },
    {
      'id': 'mechanic',
      'name': 'Mechanic to Home',
      'description': 'Mobile mechanic services – repairs at your location',
      'details':
          'Professional mobile mechanic services for car repairs, maintenance, oil changes, battery replacement, tire services, and diagnostics. We come to you with all necessary tools.',
      'color': Colors.orange,
      'icon': Icons.engineering,
      'subcategories': [
        {
          'id': 'mech_oil',
          'name': 'Oil Change',
          'description': 'Engine oil and filter change',
          'image': 'img/oil Change car.jpg',
          'iconImage': 'assets/images/mech_oil_icon.png',
        },
        {
          'id': 'mech_battery',
          'name': 'Battery Service',
          'description': 'Battery replacement and testing',
         'image': 'img/Battery Replacment.jpg',

          'iconImage': 'assets/images/mech_battery_icon.png',
        },
        {
          'id': 'mech_tire',
          'name': 'Tire Services',
          'description': 'Tire repair and replacement',
          'image': 'img/Tire Service.jpg',

          'iconImage': 'assets/images/mech_tire_icon.png',
        },
        {
          'id': 'mech_diagnostic',
          'name': 'Car Diagnostics',
          'description': 'Computer diagnostics and check',
          'image': 'img/Car diagnostics.jpg',
          'iconImage': 'assets/images/mech_diagnostic_icon.png',
        },
      ],
    },
    {
      'id': 'home_cleaning',
      'name': 'Home Cleaning',
      'description': 'Professional house cleaning and deep cleaning services',
      'details':
          'Comprehensive home cleaning services including regular cleaning, deep cleaning, window cleaning, carpet cleaning, and post-renovation cleanup. Trained and insured cleaners.',
      'color': Colors.green,
      'icon': Icons.cleaning_services,
      'subcategories': [
        {
          'id': 'clean_regular',
          'name': 'Regular Cleaning',
          'description': 'Standard house cleaning',
         'image': 'img/Regular Cleaning.jpg',
          'iconImage': 'assets/images/clean_regular_icon.png',
        },
        {
          'id': 'clean_deep',
          'name': 'Deep Cleaning',
          'description': 'Thorough deep cleaning service',
          'image': 'https://images.unsplash.com/photo-1628177142898-93e36e4e3a50?w=400&h=300&fit=crop',
          'iconImage': 'assets/images/clean_deep_icon.png',
        },
        {
          'id': 'clean_window',
          'name': 'Window Cleaning',
          'description': 'Professional window cleaning',
          'image': 'img/Window Cleaning.jpg',

          'iconImage': 'assets/images/clean_window_icon.png',
        },
        {
          'id': 'clean_carpet',
          'name': 'Carpet Cleaning',
          'description': 'Carpet and upholstery cleaning',
          'image': 'img/Carpet cleaning.jpg',
          'iconImage': 'assets/images/clean_carpet_icon.png',
        },
      ],
    },
    {
      'id': 'barber',
      'name': 'Barber to Home',
      'description': 'Mobile barber and hair styling services at home',
      'details':
          'Professional barber services at your location. Haircuts, beard trimming, styling, shaving, and grooming services. Perfect for busy schedules or special occasions.',
      'color': Colors.purple,
      'icon': Icons.content_cut,
      'subcategories': [
        {
          'id': 'barber_haircut',
          'name': 'Haircut',
          'description': 'Professional haircut service',
          'image': 'img/haircut.jpg',
          'iconImage': 'assets/images/barber_haircut_icon.png',
        },
        {
          'id': 'barber_beard',
          'name': 'Beard Trim',
          'description': 'Beard trimming and styling',
          'image': 'img/beard-trim.jpg',

          'iconImage': 'assets/images/barber_beard_icon.png',
        },
        {
          'id': 'barber_shave',
          'name': 'Shaving',
          'description': 'Traditional wet shave',
          'image': 'img/shaving.jpg',
          'iconImage': 'assets/images/barber_shave_icon.png',
        },
        {
          'id': 'barber_styling',
          'name': 'Hair Styling',
          'description': 'Hair styling and grooming',
          'image': 'https://images.unsplash.com/photo-1621605815971-fbc98d665033?w=400&h=300&fit=crop',
          'iconImage': 'assets/images/barber_styling_icon.png',
        },
      ],
    },
    {
      'id': 'elderly_care',
      'name': 'Elderly Care',
      'description': 'Compassionate caregiving and assistance for seniors',
      'details':
          'Professional elderly care services including personal care assistance, medication reminders, meal preparation, companionship, light housekeeping, and mobility assistance. Certified caregivers.',
      'color': Colors.teal,
      'icon': Icons.elderly,
      'subcategories': [
        {
          'id': 'care_personal',
          'name': 'Personal Care',
          'description': 'Assistance with daily activities',
          'image': 'img/personal care.jpg',
          'iconImage': 'assets/images/care_personal_icon.png',
        },
        {
          'id': 'care_medical',
          'name': 'Medical Assistance',
          'description': 'Medication reminders and health monitoring',
       'image': 'img/medical assistance.jpg',

          'iconImage': 'assets/images/care_medical_icon.png',
        },
        {
          'id': 'care_companion',
          'name': 'Companionship',
          'description': 'Social interaction and companionship',
          'image': 'https://images.unsplash.com/photo-1519494026892-80bbd2d6fd0d?w=400&h=300&fit=crop',
          'iconImage': 'assets/images/care_companion_icon.png',
        },
        {
          'id': 'care_meal',
          'name': 'Meal Preparation',
          'description': 'Meal planning and cooking',
          'image': 'img/meal preparation.jpg',

          'iconImage': 'assets/images/care_meal_icon.png',
        },
      ],
    },
    {
      'id': 'bill_payments',
      'name': 'Online Bill Payments',
      'description': 'Pay utility bills, subscriptions, and services online',
      'details':
          'Convenient online bill payment service for electricity, water, gas, internet, phone, TV subscriptions, and other utilities. Secure payment processing with instant confirmation.',
      'color': Colors.indigo,
      'icon': Icons.payment,
      'subcategories': [
        {
          'id': 'bill_electricity',
          'name': 'Electricity Bill',
          'description': 'Pay electricity bills online',
         'image': 'img/electricity_bill.jpg',

      
        },
        {
          'id': 'bill_water',
          'name': 'Water Bill',
          'description': 'Pay water utility bills',
         'image': 'img/water bill.jpg',

          'iconImage': 'assets/images/bill_water_icon.png',
        },
        {
          'id': 'bill_gas',
          'name': 'Gas Bill',
          'description': 'Pay gas utility bills',
          'image': 'img/gas bill.jpg',
          'iconImage': 'assets/images/bill_gas_icon.png',
        },
        {
          'id': 'bill_internet',
          'name': 'Internet & Phone',
          'description': 'Pay internet and phone bills',
         'image': 'img/internet & phone.jpg',

          'iconImage': 'assets/images/bill_internet_icon.png',
        },
      ],
    },
    {
      'id': 'dry_cleaning',
      'name': 'Dry Cleaning',
      'description': 'Pickup and delivery dry cleaning service',
      'details':
          'Professional dry cleaning and laundry services with pickup and delivery. We handle delicate fabrics, suits, formal wear, curtains, and specialty items. Free pickup and delivery included.',
      'color': Colors.pink,
      'icon': Icons.local_laundry_service,
      'subcategories': [
        {
          'id': 'dry_suits',
          'name': 'Suits & Formal Wear',
          'description': 'Dry clean suits and formal attire',
         'image': 'img/suits and formal wear.jpg',

          'iconImage': 'assets/images/dry_suits_icon.png',
        },
        {
          'id': 'dry_delicate',
          'name': 'Delicate Fabrics',
          'description': 'Special care for delicate items',
         'image': 'img/delicate fabrics.jpg',

          'iconImage': 'assets/images/dry_delicate_icon.png',
        },
        {
          'id': 'dry_curtains',
          'name': 'Curtains & Drapes',
          'description': 'Dry clean curtains and drapes',
          'image': 'img/curtains & drapes.jpg',
          'iconImage': 'assets/images/dry_curtains_icon.png',
        },
        {
          'id': 'dry_laundry',
          'name': 'Laundry Service',
          'description': 'Wash and fold laundry service',
        'image': 'img/laundry service..jpg',

          'iconImage': 'assets/images/dry_laundry_icon.png',
        },
      ],
    },
  ];
}

// ============ ARTISTIC LOGO WIDGET ============

// FixItLogo: App logo widget (uses: Row, Text, TextStyle)
class FixItLogo extends StatelessWidget {
  final double fontSize;
  final bool showIcon;
  
  const FixItLogo({
    super.key,
    this.fontSize = 28,
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (showIcon)
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.orange.shade400,
                Colors.red.shade400,
                Colors.pink.shade400,
              ],
            ).createShader(bounds),
            child: const Icon(
              Icons.build_circle,
              color: Colors.white,
              size: 26,
            ),
          ),
        if (showIcon) const SizedBox(width: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // "Fix" with vibrant gradient
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  Colors.blue.shade600,
                  Colors.purple.shade600,
                  Colors.pink.shade600,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: Text(
                'Fix',
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.5,
                  shadows: [
                    Shadow(
                      color: Colors.blue.shade900.withOpacity(0.3),
                      offset: const Offset(1, 1),
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            // "It" with warm gradient
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  Colors.orange.shade500,
                  Colors.red.shade500,
                  Colors.pink.shade500,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: Text(
                'It',
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.5,
                  shadows: [
                    Shadow(
                      color: Colors.orange.shade900.withOpacity(0.3),
                      offset: const Offset(1, 1),
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ============ FADE IN WIDGET ============

// FadeIn: Fade-in animation widget (uses: FadeIn)
class FadeIn extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const FadeIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 800),
  });

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: widget.child,
    );
  }
}

// ============ SHARED GRADIENT ICON WIDGET ============

// _GradientIcon: Gradient icon widget (uses: Text, TextStyle)
class _GradientIcon extends StatelessWidget {
  final IconData icon;
  final double size;

  const _GradientIcon(this.icon, {this.size = 24});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: [
          Colors.blue.shade600,
          Colors.purple.shade600,
          Colors.pink.shade600,
          Colors.orange.shade600,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds),
      child: Icon(
        icon,
        size: size,
        color: Colors.white,
      ),
    );
  }
}

// ============ SPLASH SCREEN ============

// FixItSplashScreen: Splash screen widget (uses: Scaffold, Column, Text, TextStyle)
class FixItSplashScreen extends StatefulWidget {
  const FixItSplashScreen({super.key});

  @override
  State<FixItSplashScreen> createState() => _FixItSplashScreenState();
}

class _FixItSplashScreenState extends State<FixItSplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Initialize app state and load saved data
    final state = _singletonAppState ??= ServiceAppState();
    await state.loadData();

    // Wait for splash screen duration
    await Future.delayed(const Duration(seconds: 4));
    
    if (!mounted) return;

    // Check if user is already logged in
    if (state.currentUser != null) {
      // Auto-login: navigate directly to main screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ServiceMainScreen(user: state.currentUser!),
        ),
      );
    } else {
      // No saved user: go to onboarding
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const ServiceOnboardingScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const FixItLogo(fontSize: 46, showIcon: true),
            const SizedBox(height: 16),
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  Colors.blue.shade600,
                  Colors.purple.shade600,
                  Colors.pink.shade600,
                  Colors.orange.shade600,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: const Text(
                'Fix your world, from home.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(height: 32),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                Colors.indigo.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============ ROOT APP ============

// FixItServiceApp: Main app widget (uses: MaterialApp)
class FixItServiceApp extends StatelessWidget {
  const FixItServiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: GlobalNavigator.key,
      debugShowCheckedModeBanner: false,
      title: 'Fix It',
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.indigo,
      ),
      home: const FixItSplashScreen(),
    );
  }
}

// ============ 1. ONBOARDING SCREEN ============

// ServiceOnboardingScreen: Onboarding screen (uses: Scaffold, SafeArea, Column, Row, Expanded, Text, TextStyle, ElevatedButton)
class ServiceOnboardingScreen extends StatelessWidget {
  const ServiceOnboardingScreen({super.key});

  final List<_OnboardPage> pages = const [
    _OnboardPage(
      title: 'Welcome to FixIt Service',
      subtitle: 'All maintenance services in one place.',
      icon: Icons.home_repair_service,
    ),
    _OnboardPage(
      title: 'Easy and Quick Booking',
      subtitle: 'Choose the service, select the date, and leave the rest to us.',
      icon: Icons.calendar_month,
    ),
    _OnboardPage(
      title: 'Track Your Orders',
      subtitle: 'You can track all orders and notifications from your device.',
      icon: Icons.notifications_active,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final PageController controller = PageController();
    int currentIndex = 0;

    return StatefulBuilder(
      builder: (context, setState) {
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: controller,
                    itemCount: pages.length,
                    onPageChanged: (i) => setState(() => currentIndex = i),
                    itemBuilder: (context, index) {
                      final page = pages[index];
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (index == 0)
                              const FixItLogo(fontSize: 42, showIcon: true)
                            else
                              Icon(
                                page.icon,
                                size: 120,
                                color: Colors.indigo,
                              ),
                            const SizedBox(height: 40),
                            if (index == 0)
                              Text(
                                page.title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            else
                              Text(
                                page.title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            const SizedBox(height: 16),
                            Text(
                              page.subtitle,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    pages.length,
                    (index) => Container(
                      margin: const EdgeInsets.all(4),
                      width: currentIndex == index ? 14 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: currentIndex == index
                            ? Colors.indigo
                            : Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ServiceRegisterScreen(),
                          ),
                        );
                      },
                      child: const Text('Get Started'),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ServiceLoginScreen(),
                      ),
                    );
                  },
                  child: const Text('Already have an account? Login'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OnboardPage {
  final String title;
  final String subtitle;
  final IconData icon;

  const _OnboardPage({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

// ============ 2. REGISTER SCREEN ============

// ServiceRegisterScreen: Registration screen (uses: Scaffold, AppBar, SingleChildScrollView, Column, Text, TextStyle, TextField, ElevatedButton, SnackBar)
class ServiceRegisterScreen extends StatefulWidget {
  const ServiceRegisterScreen({super.key});

  @override
  State<ServiceRegisterScreen> createState() => _ServiceRegisterScreenState();
}

class _ServiceRegisterScreenState extends State<ServiceRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _togglePasswordVisibility() {
    setState(() {
      _obscurePassword = !_obscurePassword;
    });
  }

  void _toggleConfirmPasswordVisibility() {
    setState(() {
      _obscureConfirmPassword = !_obscureConfirmPassword;
    });
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!value.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least one lowercase letter';
    }
    if (!value.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter';
    }
    if (!value.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number';
    }
    // Check for at least one symbol (special character)
    final hasSymbol = value.contains(RegExp(r'[!@#$%^&*()_+\-=\[\]{}|;:".<>?/~`]')) ||
                      value.contains("'") ||
                      value.contains(',');
    if (!hasSymbol) {
      return 'Password must contain at least one symbol';
    }
    return null;
  }

  // _register: Handle user registration (uses: SnackBar, showDialog)
  void _register() {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }

    final email = _emailController.text.trim().toLowerCase();
    final state = _getAppState(context);
    
    // Check if email already registered
    if (state.getUserByEmail(email) != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email already registered. Please login.')),
      );
      return;
    }

    final user = ServiceUser(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim().replaceAll(RegExp(r'[\s\-]'), ''),
      password: _passwordController.text,
    );

    state.registerUser(user);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Registration successful! Please login.')),
    );

    // Navigate to login and pass user via arguments
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const ServiceLoginScreen(),
        settings: RouteSettings(arguments: user),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const FixItLogo(fontSize: 20, showIcon: true),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.blue.shade50,
              Colors.purple.shade50,
              Colors.orange.shade50,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  children: [
                    const _GradientIcon(Icons.person_add_alt_1, size: 40),
                    const SizedBox(height: 8),
                    ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: [
                          Colors.blue.shade600,
                          Colors.purple.shade600,
                          Colors.pink.shade600,
                          Colors.orange.shade600,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds),
                      child: const Text(
                        'Create your FixIt account',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sign up once to manage all your home services.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.blue.shade50,
                          Colors.purple.shade50,
                          Colors.orange.shade50,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Full Name',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              validator: (v) => v == null || v.isEmpty
                                  ? 'Please enter your name'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                              validator: (v) => v == null || v.isEmpty
                                  ? 'Please enter your email'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _phoneController,
                              decoration: const InputDecoration(
                                labelText: 'Phone Number (010, 011, 012, or 015)',
                                hintText: '01012345678',
                                prefixIcon: Icon(Icons.phone_android),
                              ),
                              keyboardType: TextInputType.phone,
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Please enter your phone number';
                                }
                                final phone =
                                    v.trim().replaceAll(RegExp(r'[\s\-]'), '');
                                if (!RegExp(r'^\d{11}$').hasMatch(phone)) {
                                  return 'Phone number must be exactly 11 digits';
                                }
                                if (!phone.startsWith('010') &&
                                    !phone.startsWith('011') &&
                                    !phone.startsWith('012') &&
                                    !phone.startsWith('015')) {
                                  return 'Phone number must start with 010, 011, 012, or 015';
                                }
                                return null;
                              },
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(11),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _passwordController,
                              decoration: InputDecoration(
                                labelText:
                                    'Password (8+ chars: letter, symbol, number, uppercase)',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: Colors.grey[600],
                                  ),
                                  onPressed: _togglePasswordVisibility,
                                ),
                              ),
                              obscureText: _obscurePassword,
                              validator: _validatePassword,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _confirmController,
                              decoration: InputDecoration(
                                labelText: 'Confirm Password',
                                prefixIcon: const Icon(Icons.lock_reset),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureConfirmPassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: Colors.grey[600],
                                  ),
                                  onPressed: _toggleConfirmPasswordVisibility,
                                ),
                              ),
                              obscureText: _obscureConfirmPassword,
                              validator: (v) => v == null || v.isEmpty
                                  ? 'Please confirm your password'
                                  : null,
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _register,
                                child: const Text('Create Account'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ServiceLoginScreen(),
                      ),
                    );
                  },
                  child: const Text('Already have an account? Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============ 3. LOGIN SCREEN ============

// ServiceLoginScreen: Login screen (uses: Scaffold, AppBar, SingleChildScrollView, Column, Text, TextStyle, TextField, ElevatedButton, SnackBar)
class ServiceLoginScreen extends StatefulWidget {
  const ServiceLoginScreen({super.key});

  @override
  State<ServiceLoginScreen> createState() => _ServiceLoginScreenState();
}

class _ServiceLoginScreenState extends State<ServiceLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _togglePasswordVisibility() {
    setState(() {
      _obscurePassword = !_obscurePassword;
    });
  }

  // _login: Handle user login (uses: SnackBar)
  void _login() {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final state = _getAppState(context);

    // Check if user is registered and password matches
    if (!state.validateLogin(email, password)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wrong credentials')),
      );
      return;
    }

    // Get the registered user data
    final registeredUser = state.getUserByEmail(email);
    if (registeredUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wrong credentials')),
      );
      return;
    }

    // Login successful: set current user and save session
    state.loginUser(registeredUser.userData);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceMainScreen(user: registeredUser.userData),
      ),
    );
  }

  // _showForgotPasswordDialog: Show dialog to reset password
  void _showForgotPasswordDialog() {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscureOldPassword = true;
    bool obscureNewPassword = true;
    bool obscureConfirmPassword = true;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                "Reset Password",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      enabled: false,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: oldPasswordController,
                      decoration: InputDecoration(
                        labelText: 'Old Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureOldPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.grey[600],
                          ),
                          onPressed: () {
                            setDialogState(() {
                              obscureOldPassword = !obscureOldPassword;
                            });
                          },
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      obscureText: obscureOldPassword,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: newPasswordController,
                      decoration: InputDecoration(
                        labelText: 'New Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureNewPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.grey[600],
                          ),
                          onPressed: () {
                            setDialogState(() {
                              obscureNewPassword = !obscureNewPassword;
                            });
                          },
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      obscureText: obscureNewPassword,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: confirmPasswordController,
                      decoration: InputDecoration(
                        labelText: 'Confirm New Password',
                        prefixIcon: const Icon(Icons.lock_reset),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureConfirmPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.grey[600],
                          ),
                          onPressed: () {
                            setDialogState(() {
                              obscureConfirmPassword = !obscureConfirmPassword;
                            });
                          },
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      obscureText: obscureConfirmPassword,
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    oldPasswordController.dispose();
                    newPasswordController.dispose();
                    confirmPasswordController.dispose();
                    Navigator.of(dialogContext).pop();
                  },
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.blue.shade600,
                        Colors.purple.shade600,
                        Colors.pink.shade600,
                        Colors.orange.shade600,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      final email = _emailController.text.trim().toLowerCase();
                      final oldPassword = oldPasswordController.text;
                      final newPassword = newPasswordController.text;
                      final confirmPassword = confirmPasswordController.text;
                      final state = _getAppState(context);

                      // Validate inputs
                      if (oldPassword.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter your old password')),
                        );
                        return;
                      }

                      if (newPassword.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a new password')),
                        );
                        return;
                      }

                      if (newPassword.length < 8) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('New password must be at least 8 characters')),
                        );
                        return;
                      }

                      if (newPassword != confirmPassword) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('New passwords do not match')),
                        );
                        return;
                      }

                      // Check if user exists and old password is correct
                      if (!state.validateLogin(email, oldPassword)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Old password is incorrect')),
                        );
                        return;
                      }

                      // Update password
                      try {
                        state.updateEmailAndPassword(email, email, newPassword);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Password updated successfully!')),
                        );
                        oldPasswordController.dispose();
                        newPasswordController.dispose();
                        confirmPasswordController.dispose();
                        Navigator.of(dialogContext).pop();
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: ${e.toString()}')),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Reset Password',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // if came from register, prefill email
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is ServiceUser) {
      _emailController.text = args.email;
    }

    return Scaffold(
      appBar: AppBar(
        title: const FixItLogo(fontSize: 20, showIcon: true),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.orange.shade50,
              Colors.pink.shade50,
              Colors.blue.shade50,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  children: [
                    const _GradientIcon(Icons.login, size: 40),
                    const SizedBox(height: 8),
                    ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: [
                          Colors.blue.shade600,
                          Colors.purple.shade600,
                          Colors.pink.shade600,
                          Colors.orange.shade600,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds),
                      child: const Text(
                        'Welcome back to FixIt',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Login to see your services, orders and profile.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.blue.shade50,
                          Colors.purple.shade50,
                          Colors.orange.shade50,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                              validator: (v) => v == null || v.isEmpty
                                  ? 'Please enter your email'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _passwordController,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: Colors.grey[600],
                                  ),
                                  onPressed: _togglePasswordVisibility,
                                ),
                              ),
                              obscureText: _obscurePassword,
                              validator: (v) => v == null || v.isEmpty
                                  ? 'Please enter your password'
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _showForgotPasswordDialog,
                                child: Text(
                                  'Forgot your password?',
                                  style: TextStyle(color: Colors.orange.shade600),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _login,
                                child: const Text('Login'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ServiceRegisterScreen(),
                      ),
                    );
                  },
                  child: const Text('New user? Create account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============ 4. MAIN SCREEN (BOTTOM NAV) ============

// ServiceMainScreen: Main navigation screen (uses: Scaffold, AppBar, Drawer, Column, Row, Text, TextStyle)
class ServiceMainScreen extends StatefulWidget {
  final ServiceUser user;

  const ServiceMainScreen({super.key, required this.user});

  @override
  State<ServiceMainScreen> createState() => _ServiceMainScreenState();
}

class _ServiceMainScreenState extends State<ServiceMainScreen> {
  int _currentIndex = 0;
  late ServiceUser _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
  }

  void _refreshUser() {
    final state = _getAppState(context);
    if (state.currentUser != null && state.currentUser!.email == _currentUser.email) {
      setState(() {
        _currentUser = state.currentUser!;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Refresh user when switching to profile tab
    if (_currentIndex == 2) {
      _refreshUser();
    }
    
    final screens = [
      ServiceListScreen(user: _currentUser), // 5
      ServiceOrdersScreen(user: _currentUser), // 6
      ServiceProfileScreen(user: _currentUser), // 7
    ];

    return Scaffold(
      appBar: AppBar(
        title: const FixItLogo(fontSize: 22, showIcon: true),
        actions: [
          IconButton(
            icon: const _GradientIcon(Icons.notifications),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ServiceNotificationsScreen(), // 8
                ),
              );
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.blue.shade50,
                Colors.purple.shade50,
                Colors.orange.shade50,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.blue.shade600,
                      Colors.purple.shade600,
                      Colors.pink.shade600,
                      Colors.orange.shade600,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _GradientIcon(Icons.home_repair_service, size: 48),
                    const SizedBox(height: 12),
                    ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: [
                          Colors.white,
                          Colors.white.withOpacity(0.9),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds),
                      child: const Text(
                        'FixIt Service',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currentUser.email,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const _GradientIcon(Icons.home_repair_service),
                title: const Text('Services'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _currentIndex = 0);
                },
              ),
              ListTile(
                leading: const _GradientIcon(Icons.receipt_long),
                title: const Text('Orders'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _currentIndex = 1);
                },
              ),
              ListTile(
                leading: const _GradientIcon(Icons.person),
                title: const Text('Profile'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _currentIndex = 2);
                },
              ),
              const Divider(),
              ListTile(
                leading: const _GradientIcon(Icons.notifications),
                title: const Text('Notifications'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ServiceNotificationsScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.info_outline, color: Colors.blue.shade700),
                title: const Text('About'),
                onTap: () {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('About FixIt Service'),
                      content: const Text(
                        'All maintenance services in one place. Book, track, and manage your home services easily.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.logout, color: Colors.red.shade700),
                title: const Text('Logout'),
                onTap: () {
                  Navigator.pop(context);
                  // Logout and clear session
                  final state = _getAppState(context);
                  state.logoutUser();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ServiceOnboardingScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      body: screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(
            icon: _GradientIcon(Icons.home_repair_service),
            activeIcon: _GradientIcon(Icons.home_repair_service, size: 28),
            label: 'Services',
          ),
          BottomNavigationBarItem(
            icon: _GradientIcon(Icons.receipt_long),
            activeIcon: _GradientIcon(Icons.receipt_long, size: 28),
            label: 'Orders',
          ),
          BottomNavigationBarItem(
            icon: _GradientIcon(Icons.person),
            activeIcon: _GradientIcon(Icons.person, size: 28),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ============ 5. SERVICES LIST SCREEN ============

// ServiceListScreen: Services list screen (uses: ListView, Column, Row, Text, TextStyle, FadeIn)
class ServiceListScreen extends StatelessWidget {
  final ServiceUser user;

  const ServiceListScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: ServiceData.services.length,
      itemBuilder: (context, index) {
        final service = ServiceData.services[index];
        return FadeIn(
          duration: Duration(milliseconds: 300 + (index * 100)),
          child: Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.blue.shade50,
                  Colors.purple.shade50,
                  Colors.orange.shade50,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: ListTile(
            leading: CircleAvatar(
              backgroundColor: service['color'],
              child: Icon(
                service['icon'],
                color: Colors.white,
              ),
            ),
            title: ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  Colors.blue.shade600,
                  Colors.purple.shade600,
                  Colors.pink.shade600,
                  Colors.orange.shade600,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: Text(
                service['name'],
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            subtitle: Text(service['description']),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ServiceDetailsScreen(
                    user: user,
                    service: service,
                  ), // 9
                ),
              );
            },
          ),
          ),
          ),
        );
      },
    );
  }
}

// ============ 6. ORDERS LIST SCREEN ============

// _ServiceOrdersScreenHelper: Helper for order cancellation dialog (uses: showDialog, Column, Row, Text, TextStyle, ElevatedButton, SnackBar)
class _ServiceOrdersScreenHelper {
  // showCancelDialog: Show cancel booking dialog
  static void showCancelDialog(BuildContext context, ServiceBooking booking, ServiceAppState appState) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.red,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Cancel Order',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Are you sure you want to cancel this order?',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.serviceName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${booking.province} - ${booking.dateTime.day}/${booking.dateTime.month}/${booking.dateTime.year}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: Text(
                'No',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                appState.cancelBooking(booking);
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white),
                        SizedBox(width: 8),
                        Text('Order cancelled successfully'),
                      ],
                    ),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Yes, Cancel'),
            ),
          ],
        );
      },
    );
  }
}

// ServiceOrdersScreen: Orders list with TabBar (uses: Column, Row, Text, TextStyle, TabBar, Expanded, ListView)
class ServiceOrdersScreen extends StatefulWidget {
  final ServiceUser user;

  const ServiceOrdersScreen({super.key, required this.user});

  @override
  State<ServiceOrdersScreen> createState() => _ServiceOrdersScreenState();
}

class _ServiceOrdersScreenState extends State<ServiceOrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Color _getServiceColor(String serviceName) {
    for (var service in ServiceData.services) {
      if (serviceName.contains(service['name'] as String)) {
        return service['color'] as Color;
      }
    }
    return Colors.grey;
  }

  IconData _getServiceIcon(String serviceName) {
    for (var service in ServiceData.services) {
      if (serviceName.contains(service['name'] as String)) {
        return service['icon'] as IconData;
      }
    }
    return Icons.receipt_long;
  }

  String _getStatus(ServiceBooking booking) {
    if (booking.isCancelled) {
      return 'Cancelled';
    }
    final bookingDate = booking.dateTime;
    final now = DateTime.now();
    if (bookingDate.isBefore(now)) {
      return 'Completed';
    } else if (bookingDate.difference(now).inDays <= 1) {
      return 'Upcoming';
    } else {
      return 'Scheduled';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Completed':
        return Colors.green;
      case 'Upcoming':
        return Colors.orange;
      case 'Cancelled':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  // _getFilteredBookings: Filter bookings by current user and tab selection
  List<ServiceBooking> _getFilteredBookings(List<ServiceBooking> bookings, String? userEmail) {
    // First filter by current user
    final userBookings = userEmail != null
        ? bookings.where((booking) => booking.userEmail.toLowerCase() == userEmail.toLowerCase()).toList()
        : bookings;
    
    // Then filter by tab selection
    final selectedIndex = _tabController.index;
    if (selectedIndex == 0) {
      return userBookings; // All
    }
    return userBookings.where((booking) {
      final status = _getStatus(booking);
      switch (selectedIndex) {
        case 1:
          return status == 'Scheduled';
        case 2:
          return status == 'Upcoming';
        case 3:
          return status == 'Completed';
        case 4:
          return status == 'Cancelled';
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final appState = _getAppState(context);
    final userEmail = appState.currentUser?.email.toLowerCase();
    final userBookings = _getFilteredBookings(appState.bookings, userEmail);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _GradientIcon(Icons.receipt_long, size: 26),
              const SizedBox(width: 8),
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [
                    Colors.blue.shade600,
                    Colors.purple.shade600,
                    Colors.pink.shade600,
                    Colors.orange.shade600,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(bounds),
                child: const Text(
                  'Your Orders',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Track and manage all your FixIt bookings.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: Colors.blue.shade700,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blue.shade700,
            tabs: const [
              Tab(text: 'All'),
              Tab(text: 'Scheduled'),
              Tab(text: 'Upcoming'),
              Tab(text: 'Completed'),
              Tab(text: 'Cancelled'),
            ],
            onTap: (index) {
              setState(() {});
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: userBookings.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No orders yet',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Book a service to see your orders here',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  )
                : _buildOrdersList(context, userBookings, appState),
          ),
        ],
      ),
    );
  }

  // _buildOrdersList: Build orders list widget
  Widget _buildOrdersList(BuildContext context, List<ServiceBooking> bookings, ServiceAppState appState) {
    if (bookings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.filter_alt_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No orders in this category',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: bookings.length,
      itemBuilder: (context, index) {
        final booking = bookings[index];
        final serviceColor = _getServiceColor(booking.serviceName);
        final serviceIcon = _getServiceIcon(booking.serviceName);
        final status = _getStatus(booking);
        final statusColor = _getStatusColor(status);

                      return Card(
                        elevation: 3,
                        margin: const EdgeInsets.only(bottom: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ServiceOrderDetailsScreen(
                                  booking: booking,
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: booking.isCancelled
                                  ? Border.all(
                                      color: Colors.red,
                                      width: 2,
                                    )
                                  : Border(
                                      left: BorderSide(
                                        color: serviceColor,
                                        width: 5,
                                      ),
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
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: booking.isCancelled
                                              ? Colors.red.withOpacity(0.1)
                                              : serviceColor.withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          serviceIcon,
                                          color: booking.isCancelled
                                              ? Colors.red
                                              : serviceColor,
                                          size: 28,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              booking.serviceName,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.location_on,
                                                  size: 16,
                                                  color: Colors.grey[600],
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  booking.province,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.grey[700],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: statusColor.withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          status,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: statusColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.calendar_today,
                                              size: 18,
                                              color: Colors.grey[600],
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '${booking.dateTime.day}/${booking.dateTime.month}/${booking.dateTime.year}',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey[700],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.access_time,
                                              size: 18,
                                              color: Colors.grey[600],
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              TimeOfDay.fromDateTime(
                                                      booking.dateTime)
                                                  .format(context),
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey[700],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (!booking.isCancelled)
                                        IconButton(
                                          icon: Icon(
                                            Icons.cancel_outlined,
                                            color: Colors.red.shade400,
                                            size: 20,
                                          ),
                                          onPressed: () {
                                            _ServiceOrdersScreenHelper
                                                .showCancelDialog(
                                                    context, booking, appState);
                                          },
                                          tooltip: 'Cancel Order',
                                        )
                                      else
                                        const SizedBox(width: 40),
                                      Icon(
                                        Icons.arrow_forward_ios,
                                        size: 16,
                                        color: Colors.grey[400],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
    );
  }
}

// ============ 7. PROFILE SCREEN ============

// ServiceProfileScreen: User profile screen (uses: Column, Row, Text, TextStyle, SingleChildScrollView, ElevatedButton)
class ServiceProfileScreen extends StatefulWidget {
  final ServiceUser user;

  const ServiceProfileScreen({super.key, required this.user});

  @override
  State<ServiceProfileScreen> createState() => _ServiceProfileScreenState();
}

class _ServiceProfileScreenState extends State<ServiceProfileScreen> {
  late ServiceUser _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
  }

  void _refreshProfile() {
    final state = _getAppState(context);
    if (state.currentUser != null) {
      setState(() {
        _currentUser = state.currentUser!;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.shade50,
            Colors.purple.shade50,
            Colors.orange.shade50,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            // Profile Header Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.blue.shade600,
                      Colors.purple.shade600,
                      Colors.pink.shade600,
                      Colors.orange.shade600,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: [
                          Colors.white,
                          Colors.white.withOpacity(0.9),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds),
                      child: Text(
                        _currentUser.name,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _currentUser.email,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Profile Information Card
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.blue.shade50,
                      Colors.purple.shade50,
                      Colors.orange.shade50,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const _GradientIcon(Icons.person, size: 24),
                        const SizedBox(width: 12),
                        ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: [
                              Colors.blue.shade600,
                              Colors.purple.shade600,
                              Colors.pink.shade600,
                              Colors.orange.shade600,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ).createShader(bounds),
                          child: const Text(
                            'Profile Information',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildInfoRow(
                      icon: Icons.person_outline,
                      label: 'Full Name',
                      value: _currentUser.name,
                    ),
                    const Divider(height: 32),
                    _buildInfoRow(
                      icon: Icons.email_outlined,
                      label: 'Email',
                      value: _currentUser.email,
                    ),
                    const Divider(height: 32),
                    _buildInfoRow(
                      icon: Icons.phone_outlined,
                      label: 'Phone',
                      value: _currentUser.phone,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Edit Profile Button
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.blue.shade600,
                    Colors.purple.shade600,
                    Colors.pink.shade600,
                    Colors.orange.shade600,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditServiceProfileScreen(user: _currentUser),
                    ),
                  );
                  if (result == true) {
                    _refreshProfile();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.edit_outlined, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Edit Profile',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Logout Button
            Container(
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.red.shade200,
                  width: 1.5,
                ),
              ),
              child: ElevatedButton(
                onPressed: () {
                  // Logout: clear current user and save state
                  final state = _getAppState(context);
                  state.logoutUser();
                  
                  // Navigate to login screen
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ServiceLoginScreen(),
                    ),
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'Logout',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: Colors.blue.shade700,
            size: 20,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============ 8. NOTIFICATIONS SCREEN ============

// ServiceNotificationsScreen: Notifications list screen (uses: Scaffold, AppBar, ListView, Text, TextStyle)
class ServiceNotificationsScreen extends StatelessWidget {
  const ServiceNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = _getAppState(context);

    return Scaffold(
      appBar: AppBar(
        title: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [
              Colors.purple.shade600,
              Colors.pink.shade600,
              Colors.orange.shade600,
              Colors.red.shade600,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            'Notifications',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
      body: state.notifications.isEmpty
          ? const Center(child: Text('No notifications yet.'))
          : ListView.builder(
              itemCount: state.notifications.length,
              itemBuilder: (context, index) {
                final n = state.notifications[index];
                return Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.indigo.withOpacity(0.4),
                      width: 1.5,
                    ),
                    color: Colors.indigo.withOpacity(0.02),
                  ),
                  child: ListTile(
                    leading:
                        const _GradientIcon(Icons.notifications, size: 26),
                    title: Text(n.message),
                    subtitle: Text(
                      '${n.createdAt.day}/${n.createdAt.month}/${n.createdAt.year}',
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ============ 9. SERVICE DETAILS SCREEN ============

// ServiceDetailsScreen: Service details with ExpansionTile (uses: Scaffold, AppBar, SingleChildScrollView, Column, Row, Text, TextStyle, ExpansionTile, GridView, Image)
class ServiceDetailsScreen extends StatelessWidget {
  final ServiceUser user;
  final Map<String, dynamic> service;

  const ServiceDetailsScreen({
    super.key,
    required this.user,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final subcategories = service['subcategories'] as List<dynamic>? ?? [];
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            _GradientIcon(service['icon'] as IconData, size: 24),
            const SizedBox(width: 8),
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  Colors.blue.shade600,
                  Colors.purple.shade600,
                  Colors.pink.shade600,
                  Colors.orange.shade600,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: Text(
                service['name'] as String,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: service['color'],
                  child: Icon(service['icon'], color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    service['description'] as String,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              service['details'] as String,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 20),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ExpansionTile(
                leading: Icon(
                  Icons.info_outline,
                  color: service['color'] as Color,
                ),
                title: const Text(
                  'Service Information',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Available Areas:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          provinces.join(', '),
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Service Details:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          service['details'] as String,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(
                  Icons.apps,
                  size: 24,
                  color: service['color'] as Color,
                ),
                const SizedBox(width: 8),
                Text(
                  'Available Services',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[900],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (subcategories.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No subcategories available'),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.85,
                ),
                itemCount: subcategories.length,
                itemBuilder: (context, index) {
                  final subcategory = subcategories[index] as Map<String, dynamic>;
                  return Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ServiceBookingScreen(
                              user: user,
                              serviceName: '${service['name']} - ${subcategory['name']}',
                            ),
                          ),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            colors: [
                              (service['color'] as Color).withOpacity(0.15),
                              Colors.white,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(
                            color:
                                (service['color'] as Color).withOpacity(0.4),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (service['color'] as Color)
                                  .withOpacity(0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(12),
                                ),
                                child: Image.network(
                                  subcategory['image'] as String,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    // Retry loading the image instead of showing icon
                                    return Image.network(
                                      subcategory['image'] as String,
                                      fit: BoxFit.cover,
                                    );
                                  },
                                  loadingBuilder:
                                      (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      color: (service['color'] as Color)
                                          .withOpacity(0.2),
                                      child: const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: Image.network(
                                          subcategory['image'] as String,
                                          width: 20,
                                          height: 20,
                                          fit: BoxFit.cover,
                                          cacheWidth: 40,
                                          cacheHeight: 40,
                                          errorBuilder: (context, error, stackTrace) {
                                            // Retry loading the image
                                            return Image.network(
                                              subcategory['image'] as String,
                                              width: 20,
                                              height: 20,
                                              fit: BoxFit.cover,
                                            );
                                          },
                                          loadingBuilder: (context, child, loadingProgress) {
                                            if (loadingProgress == null) return child;
                                            return Container(
                                              width: 20,
                                              height: 20,
                                              decoration: BoxDecoration(
                                                color: Colors.grey[200],
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Center(
                                                child: SizedBox(
                                                  width: 8,
                                                  height: 8,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 1,
                                                    value: loadingProgress.expectedTotalBytes != null
                                                        ? loadingProgress.cumulativeBytesLoaded /
                                                            loadingProgress.expectedTotalBytes!
                                                        : null,
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          subcategory['name'] as String,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Colors.black87,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    subcategory['description'] as String,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[700],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ============ 10. ORDER DETAILS SCREEN ============

// ServiceOrderDetailsScreen: Order details screen (uses: Scaffold, AppBar, SingleChildScrollView, Column, Row, Text, TextStyle, Image)
class ServiceOrderDetailsScreen extends StatelessWidget {
  final ServiceBooking booking;

  const ServiceOrderDetailsScreen({super.key, required this.booking});

  // _getServiceColor: Get service color
  Color _getServiceColor(String serviceName) {
    for (var service in ServiceData.services) {
      if (serviceName.contains(service['name'] as String)) {
        return service['color'] as Color;
      }
    }
    return Colors.grey;
  }

  IconData _getServiceIcon(String serviceName) {
    for (var service in ServiceData.services) {
      if (serviceName.contains(service['name'] as String)) {
        return service['icon'] as IconData;
      }
    }
    return Icons.receipt_long;
  }

  String _getStatus(ServiceBooking booking) {
    if (booking.isCancelled) {
      return 'Cancelled';
    }
    final bookingDate = booking.dateTime;
    final now = DateTime.now();
    if (bookingDate.isBefore(now)) {
      return 'Completed';
    } else if (bookingDate.difference(now).inDays <= 1) {
      return 'Upcoming';
    } else {
      return 'Scheduled';
    }
  }

  // _getStatusColor: Get status color
  Color _getStatusColor(String status) {
    switch (status) {
      case 'Completed':
        return Colors.green;
      case 'Upcoming':
        return Colors.orange;
      case 'Cancelled':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final serviceColor = _getServiceColor(booking.serviceName);
    final serviceIcon = _getServiceIcon(booking.serviceName);
    final status = _getStatus(booking);
    final statusColor = _getStatusColor(status);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const _GradientIcon(Icons.receipt_long, size: 24),
            const SizedBox(width: 8),
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  Colors.blue.shade600,
                  Colors.purple.shade600,
                  Colors.pink.shade600,
                  Colors.orange.shade600,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: const Text(
                'Order Details',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header Section with Color
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    booking.isCancelled
                        ? Colors.red.shade700
                        : serviceColor,
                    booking.isCancelled
                        ? Colors.red.shade400
                        : serviceColor.withOpacity(0.7),
                  ],
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      serviceIcon,
                      size: 50,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    booking.serviceName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Details Section
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Location Card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.red,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Location',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  booking.province,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Date & Time Card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.calendar_today,
                                  color: Colors.blue,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Date',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${booking.dateTime.day}/${booking.dateTime.month}/${booking.dateTime.year}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 32),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.access_time,
                                  color: Colors.purple,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Time',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      TimeOfDay.fromDateTime(booking.dateTime)
                                          .format(context),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Notes Card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.note,
                                  color: Colors.orange,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Text(
                                'Additional Notes',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              booking.notes.isEmpty
                                  ? 'No additional notes provided'
                                  : booking.notes,
                              style: TextStyle(
                                fontSize: 14,
                                color: booking.notes.isEmpty
                                    ? Colors.grey[600]
                                    : Colors.black87,
                                fontStyle: booking.notes.isEmpty
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============ 11. EDIT PROFILE SCREEN ============

// EditServiceProfileScreen: Edit profile screen (uses: Scaffold, AppBar, SingleChildScrollView, Column, Text, TextStyle, TextField, ElevatedButton)
class EditServiceProfileScreen extends StatefulWidget {
  final ServiceUser user;

  const EditServiceProfileScreen({super.key, required this.user});

  @override
  State<EditServiceProfileScreen> createState() =>
      _EditServiceProfileScreenState();
}

class _EditServiceProfileScreenState extends State<EditServiceProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _passwordController;
  late TextEditingController _confirmPasswordController;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.name);
    _emailController = TextEditingController(text: widget.user.email);
    _phoneController = TextEditingController(text: widget.user.phone);
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your phone number';
    }
    
    // Remove any spaces or dashes
    final phone = value.trim().replaceAll(RegExp(r'[\s\-]'), '');
    
    // Check if it's exactly 11 digits
    if (!RegExp(r'^\d{11}$').hasMatch(phone)) {
      return 'Phone number must be exactly 11 digits';
    }
    
    // Check if it starts with 010, 011, 012, or 015
    if (!phone.startsWith('010') && 
        !phone.startsWith('011') && 
        !phone.startsWith('012') && 
        !phone.startsWith('015')) {
      return 'Phone number must start with 010, 011, 012, or 015';
    }
    
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value != null && value.isNotEmpty) {
      if (value.length < 6) {
        return 'Password must be at least 6 characters';
      }
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (_passwordController.text.isNotEmpty) {
      if (value == null || value.isEmpty) {
        return 'Please confirm your password';
      }
      if (value != _passwordController.text) {
        return 'Passwords do not match';
      }
    }
    return null;
  }

  // _saveChanges: Save profile changes
  void _saveChanges() {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final phone = _phoneController.text.trim().replaceAll(RegExp(r'[\s\-]'), '');
    final password = _passwordController.text;
    final state = _getAppState(context);

    try {
      // Update email and/or password if changed
      if (email != widget.user.email.toLowerCase() || password.isNotEmpty) {
        state.updateEmailAndPassword(widget.user.email, email, password.isNotEmpty ? password : null);
      }

      // Update name and phone
      state.updateUserProfile(email, name, phone);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true); // Return true to indicate success
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const _GradientIcon(Icons.person, size: 24),
            const SizedBox(width: 8),
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  Colors.blue.shade600,
                  Colors.purple.shade600,
                  Colors.pink.shade600,
                  Colors.orange.shade600,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: const Text(
                'Edit Profile',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.blue.shade50,
              Colors.purple.shade50,
              Colors.orange.shade50,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                // Profile Header
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.blue.shade600,
                          Colors.purple.shade600,
                          Colors.pink.shade600,
                          Colors.orange.shade600,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 50,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Personal Information Card
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.blue.shade50,
                          Colors.purple.shade50,
                          Colors.orange.shade50,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const _GradientIcon(Icons.person_outline, size: 24),
                            const SizedBox(width: 12),
                            ShaderMask(
                              shaderCallback: (bounds) => LinearGradient(
                                colors: [
                                  Colors.blue.shade600,
                                  Colors.purple.shade600,
                                  Colors.pink.shade600,
                                  Colors.orange.shade600,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ).createShader(bounds),
                              child: const Text(
                                'Personal Information',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'Full Name',
                            prefixIcon: const Icon(Icons.person_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          validator: (v) => v == null || v.isEmpty
                              ? 'Please enter your name'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _phoneController,
                          decoration: InputDecoration(
                            labelText: 'Phone (010, 011, 012, or 015)',
                            hintText: '01012345678',
                            prefixIcon: const Icon(Icons.phone),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          keyboardType: TextInputType.phone,
                          validator: _validatePhone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(11),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Account Security Card
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.blue.shade50,
                          Colors.purple.shade50,
                          Colors.orange.shade50,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const _GradientIcon(Icons.lock_outline, size: 24),
                            const SizedBox(width: 12),
                            ShaderMask(
                              shaderCallback: (bounds) => LinearGradient(
                                colors: [
                                  Colors.blue.shade600,
                                  Colors.purple.shade600,
                                  Colors.pink.shade600,
                                  Colors.orange.shade600,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ).createShader(bounds),
                              child: const Text(
                                'Account Security',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _emailController,
                          decoration: InputDecoration(
                            labelText: 'Email Address',
                            prefixIcon: const Icon(Icons.email_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: _validateEmail,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          decoration: InputDecoration(
                            labelText: 'New Password (leave empty to keep current)',
                            hintText: 'Enter new password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          obscureText: _obscurePassword,
                          validator: _validatePassword,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmPasswordController,
                          decoration: InputDecoration(
                            labelText: 'Confirm New Password',
                            hintText: 'Re-enter new password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureConfirmPassword = !_obscureConfirmPassword;
                                });
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          obscureText: _obscureConfirmPassword,
                          validator: _validateConfirmPassword,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Save Button
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.blue.shade600,
                        Colors.purple.shade600,
                        Colors.pink.shade600,
                        Colors.orange.shade600,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _saveChanges,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.save_outlined, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Save Changes',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============ 12. BOOKING SCREEN (CALENDAR + TIME) ============

// ServiceBookingScreen: Booking screen with gradient (uses: Scaffold, AppBar, SingleChildScrollView, Column, Row, Text, TextStyle, TextField, ElevatedButton, showDialog)
class ServiceBookingScreen extends StatefulWidget {
  final ServiceUser user;
  final String serviceName;

  const ServiceBookingScreen({
    super.key,
    required this.user,
    required this.serviceName,
  });

  @override
  State<ServiceBookingScreen> createState() => _ServiceBookingScreenState();
}

class _ServiceBookingScreenState extends State<ServiceBookingScreen> {
  String? _selectedProvince;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time != null) {
      setState(() => _selectedTime = time);
    }
  }

  // _confirmBooking: Confirm and save booking
  void _confirmBooking() {
    if (_selectedProvince == null ||
        _selectedDate == null ||
        _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select province, date, and time')),
      );
      return;
    }

    final dateTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    final state = _getAppState(context);
    if (state.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to book a service')),
      );
      return;
    }

    final booking = ServiceBooking(
      serviceName: widget.serviceName,
      province: _selectedProvince!,
      dateTime: dateTime,
      notes: _notesController.text.trim(),
      userEmail: state.currentUser!.email.toLowerCase(),
    );

    state.addBooking(booking);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Booking Confirmed'),
        content: const Text('Service booked successfully.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const _GradientIcon(Icons.calendar_month, size: 24),
            const SizedBox(width: 8),
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  Colors.blue.shade600,
                  Colors.purple.shade600,
                  Colors.pink.shade600,
                  Colors.orange.shade600,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: Text(
                'Book ${widget.serviceName}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.blue.shade50,
              Colors.purple.shade50,
              Colors.orange.shade50,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Schedule your visit',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[900],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Choose where and when our team should arrive.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            labelText: 'Select Province',
                            prefixIcon:
                                const Icon(Icons.location_on_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: provinces
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(e),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedProvince = v),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickDate,
                                icon: const Icon(Icons.calendar_today_outlined),
                                label: Text(
                                  _selectedDate == null
                                      ? 'Select Date'
                                      : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickTime,
                                icon: const Icon(Icons.access_time),
                                label: Text(
                                  _selectedTime == null
                                      ? 'Select Time'
                                      : _selectedTime!.format(context),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _notesController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'Additional Notes (Optional)',
                            alignLabelWithHint: true,
                            prefixIcon: const Icon(Icons.notes_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _confirmBooking,
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Confirm Booking'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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

// Helper to get or create a simple global state instance
// _getAppState: Get app state instance
ServiceAppState _getAppState(BuildContext context) {
  // In this simplified example, we keep a single instance in Navigator context
  // via an InheritedWidget-like pattern; for real apps use Provider/Riverpod.
  final navigatorContext = GlobalNavigator.key.currentContext;
  if (navigatorContext == null) {
    // Fallback single instance
    _singletonAppState ??= ServiceAppState();
    return _singletonAppState!;
  }
  _singletonAppState ??= ServiceAppState();
  return _singletonAppState!;
}

ServiceAppState? _singletonAppState;

//sdddd